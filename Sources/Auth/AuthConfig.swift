import Foundation

enum AuthConfig {
    /// Google OAuth Desktop client. Provided via `.env` and generated into `Sources/Generated/Secrets.swift`.
    /// Google's Desktop OAuth requires the client_secret in token exchange even with PKCE.
    static let clientID: String = Secrets.googleClientID
    static let clientSecret: String = Secrets.googleClientSecret

    static let scopes: [String] = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/calendar.events.readonly",
        "openid",
        "email",
        "profile"
    ]

    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revocationEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    static let userInfoEndpoint = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!
}
