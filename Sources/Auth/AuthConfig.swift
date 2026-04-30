import Foundation

enum AuthConfig {
    /// Google OAuth Desktop client ID. Provided via `.env` and generated into `Sources/Generated/Secrets.swift`.
    /// See README.md and `scripts/generate-secrets.sh`.
    static let clientID: String = Secrets.googleClientID

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
