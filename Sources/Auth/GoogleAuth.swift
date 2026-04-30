import Foundation
import AuthenticationServices
import AppKit

enum AuthError: Error, LocalizedError {
    case missingClientID
    case userCancelled
    case noAuthorizationCode
    case tokenExchangeFailed(String)
    case userInfoFailed
    case clientIDNotConfigured

    var errorDescription: String? {
        switch self {
        case .missingClientID: return "Missing OAuth client ID."
        case .userCancelled: return "Sign-in was cancelled."
        case .noAuthorizationCode: return "Google did not return an authorisation code."
        case .tokenExchangeFailed(let m): return "Token exchange failed: \(m)"
        case .userInfoFailed: return "Failed to fetch user info."
        case .clientIDNotConfigured:
            return "OAuth client ID not configured. Edit Sources/Auth/AuthConfig.swift or set CALLY_GOOGLE_CLIENT_ID."
        }
    }
}

@MainActor
final class GoogleAuth: NSObject {
    static let shared = GoogleAuth()

    private var loopbackServer: LoopbackServer?

    func signIn() async throws -> (account: GoogleAccount, tokens: OAuthTokens) {
        guard !AuthConfig.clientID.isEmpty else {
            throw AuthError.clientIDNotConfigured
        }

        let server = try await LoopbackServer.start()
        loopbackServer = server
        defer {
            server.stop()
            loopbackServer = nil
        }

        let verifier = PKCE.generateVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = UUID().uuidString
        let redirectURI = "http://127.0.0.1:\(server.port)/callback"

        var components = URLComponents(url: AuthConfig.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: AuthConfig.clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: AuthConfig.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]
        let authURL = components.url!

        async let codeAwait = server.waitForCode(expectedState: state)
        NSWorkspace.shared.open(authURL)
        let code = try await codeAwait

        let tokens = try await exchangeCode(code, verifier: verifier, redirectURI: redirectURI)
        let account = try await fetchUserInfo(accessToken: tokens.accessToken)
        account.saveAsPrimary()
        tokens.save(for: account.id)
        return (account, tokens)
    }

    func refreshIfNeeded(account: GoogleAccount) async throws -> OAuthTokens {
        guard var tokens = OAuthTokens.load(for: account.id) else {
            throw AuthError.tokenExchangeFailed("No stored tokens")
        }
        if !tokens.isExpired { return tokens }

        var req = URLRequest(url: AuthConfig.tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": AuthConfig.clientID,
            "client_secret": AuthConfig.clientSecret,
            "refresh_token": tokens.refreshToken,
            "grant_type": "refresh_token"
        ]
        req.httpBody = body.formURLEncoded()
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw AuthError.tokenExchangeFailed(msg)
        }
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        tokens.accessToken = resp.access_token
        tokens.expiresAt = Date().addingTimeInterval(TimeInterval(resp.expires_in))
        if let id = resp.id_token { tokens.idToken = id }
        tokens.save(for: account.id)
        return tokens
    }

    func signOut(account: GoogleAccount) async {
        if let tokens = OAuthTokens.load(for: account.id) {
            var req = URLRequest(url: AuthConfig.revocationEndpoint)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = ["token": tokens.refreshToken].formURLEncoded()
            _ = try? await URLSession.shared.data(for: req)
        }
        GoogleAccount.clearPrimary()
    }

    private func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws -> OAuthTokens {
        var req = URLRequest(url: AuthConfig.tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": AuthConfig.clientID,
            "client_secret": AuthConfig.clientSecret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        req.httpBody = body.formURLEncoded()
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw AuthError.tokenExchangeFailed(msg)
        }
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = resp.refresh_token else {
            throw AuthError.tokenExchangeFailed("No refresh_token in response")
        }
        return OAuthTokens(
            accessToken: resp.access_token,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(resp.expires_in)),
            idToken: resp.id_token
        )
    }

    private func fetchUserInfo(accessToken: String) async throws -> GoogleAccount {
        var req = URLRequest(url: AuthConfig.userInfoEndpoint)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.userInfoFailed
        }
        struct UserInfo: Decodable {
            let sub: String
            let email: String
            let name: String?
            let picture: String?
        }
        let info = try JSONDecoder().decode(UserInfo.self, from: data)
        return GoogleAccount(id: info.sub, email: info.email, name: info.name, pictureURL: info.picture)
    }
}

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
    let id_token: String?
    let scope: String?
    let token_type: String?
}

extension Dictionary where Key == String, Value == String {
    func formURLEncoded() -> Data {
        let parts = self.map { (k, v) -> String in
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? v
            return "\(ek)=\(ev)"
        }
        return Data(parts.joined(separator: "&").utf8)
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var s = CharacterSet.urlQueryAllowed
        s.remove(charactersIn: "&=+")
        return s
    }()
}
