import Foundation
import Network

private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    /// Atomically sets the flag and returns true if this call was the one that set it.
    func set() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if value { return false }
        value = true
        return true
    }
}

/// Tiny loopback HTTP server used to receive the OAuth redirect on 127.0.0.1.
/// Listens for one GET /callback?code=...&state=..., responds with a small HTML page,
/// then yields the code via continuation.
///
/// All access to `continuation` and `expectedState` is serialised through `stateQueue`
/// so that concurrent Network.framework callbacks (e.g. the real /callback racing a
/// browser favicon probe) cannot double-resume the continuation.
final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let stateQueue = DispatchQueue(label: "cally.loopback.state")
    private var continuation: CheckedContinuation<String, Error>?
    private var expectedState: String?

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    private init(listener: NWListener) {
        self.listener = listener
    }

    static func start() async throws -> LoopbackServer {
        // Bind to the loopback interface only. Without this, NWListener listens on
        // all interfaces and any host on the LAN can race the browser to deliver a
        // forged code on the ephemeral port.
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.acceptLocalOnly = true
        let listener = try NWListener(using: params)
        let server = LoopbackServer(listener: listener)

        listener.newConnectionHandler = { [weak server] connection in
            server?.handle(connection: connection)
        }

        let resumed = AtomicFlag()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.set() { cont.resume() }
                case .failed(let err):
                    if resumed.set() { cont.resume(throwing: err) }
                case .cancelled:
                    if resumed.set() {
                        cont.resume(throwing: AuthError.tokenExchangeFailed("Loopback cancelled"))
                    }
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }

        return server
    }

    func waitForCode(expectedState: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            stateQueue.async {
                self.expectedState = expectedState
                self.continuation = cont
            }
        }
    }

    func stop() {
        listener.cancel()
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveHeaders(on: connection, accumulated: Data())
    }

    /// Read until we've seen the end of the HTTP request headers (`\r\n\r\n`).
    /// Network.framework can split a request across multiple receives; the previous
    /// single-shot read assumed the whole request fitted in one TCP chunk.
    private func receiveHeaders(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let data { buffer.append(data) }

            let terminator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
            if buffer.range(of: terminator) != nil {
                let request = String(data: buffer, encoding: .utf8) ?? ""
                self.process(request: request, on: connection)
                return
            }

            // Cap buffer to avoid an attacker streaming bytes forever.
            if buffer.count >= 16_384 || isComplete {
                self.send(html: "<h1>Bad request</h1>", status: "400 Bad Request", to: connection)
                return
            }

            self.receiveHeaders(on: connection, accumulated: buffer)
        }
    }

    private func process(request: String, on connection: NWConnection) {
        let firstLine = request.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            send(html: "<h1>Bad request</h1>", status: "400 Bad Request", to: connection)
            return
        }
        let path = String(parts[1])
        let url = URL(string: "http://127.0.0.1\(path)")
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let pathOnly = components?.path ?? path
        let items = components?.queryItems ?? []

        // Ignore anything that isn't the OAuth callback (favicon probes, browser
        // pre-flights, etc.). Resuming the continuation for these would kill sign-in
        // before the real /callback arrives.
        guard pathOnly == "/callback" else {
            send(html: "<h1>Not found</h1>", status: "404 Not Found", to: connection)
            return
        }

        let code = items.first(where: { $0.name == "code" })?.value
        let state = items.first(where: { $0.name == "state" })?.value
        let error = items.first(where: { $0.name == "error" })?.value

        // Only resume on a definitive answer (success or explicit error). Anything
        // else (missing code, missing state, no error) is treated as a malformed
        // probe and ignored.
        guard code != nil || error != nil else {
            send(html: "<h1>Bad request</h1>", status: "400 Bad Request", to: connection)
            return
        }

        stateQueue.async { [weak self] in
            guard let self else {
                connection.cancel()
                return
            }
            guard let cont = self.continuation else {
                self.send(html: "<h1>Not expected</h1>", status: "400 Bad Request", to: connection)
                return
            }
            self.continuation = nil
            let expected = self.expectedState
            self.expectedState = nil

            if let code, state == expected {
                let body = """
                <!doctype html>
                <html><head><meta charset="utf-8"><title>Cally — Signed In</title>
                <style>body{font-family:-apple-system,Helvetica;background:#111;color:#eee;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}.card{text-align:center;padding:40px}h1{margin:0 0 8px;font-weight:600}p{opacity:.7}</style>
                </head><body><div class="card"><h1>Signed in to Cally</h1><p>You can close this window.</p></div></body></html>
                """
                self.send(html: body, status: "200 OK", to: connection)
                cont.resume(returning: code)
            } else {
                let body = """
                <h1>Sign-in failed</h1><p>\(error ?? "Unknown error"). You can close this window.</p>
                """
                self.send(html: body, status: "400 Bad Request", to: connection)
                cont.resume(throwing: AuthError.noAuthorizationCode)
            }
        }
    }

    private func send(html: String, status: String, to connection: NWConnection) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
