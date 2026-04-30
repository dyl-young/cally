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
final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private var continuation: CheckedContinuation<String, Error>?
    private var expectedState: String?

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    private init(listener: NWListener) {
        self.listener = listener
    }

    static func start() async throws -> LoopbackServer {
        let listener = try NWListener(using: .tcp, on: .any)
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
        self.expectedState = expectedState
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }

    func stop() {
        listener.cancel()
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            self.process(request: request, on: connection)
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
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        let code = items.first(where: { $0.name == "code" })?.value
        let state = items.first(where: { $0.name == "state" })?.value
        let error = items.first(where: { $0.name == "error" })?.value

        if let code, state == expectedState {
            let body = """
            <!doctype html>
            <html><head><meta charset="utf-8"><title>Cally — Signed In</title>
            <style>body{font-family:-apple-system,Helvetica;background:#111;color:#eee;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}.card{text-align:center;padding:40px}h1{margin:0 0 8px;font-weight:600}p{opacity:.7}</style>
            </head><body><div class="card"><h1>Signed in to Cally</h1><p>You can close this window.</p></div></body></html>
            """
            send(html: body, status: "200 OK", to: connection)
            continuation?.resume(returning: code)
            continuation = nil
        } else {
            let body = """
            <h1>Sign-in failed</h1><p>\(error ?? "Unknown error"). You can close this window.</p>
            """
            send(html: body, status: "400 Bad Request", to: connection)
            continuation?.resume(throwing: AuthError.noAuthorizationCode)
            continuation = nil
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
