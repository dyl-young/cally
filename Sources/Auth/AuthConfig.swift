import Foundation

enum AuthConfig {
    /// Google OAuth Desktop client ID. Create one at https://console.cloud.google.com
    /// → APIs & Services → Credentials → Create OAuth client → Desktop app.
    /// Paste the client ID here. No client secret is needed (PKCE).
    static let clientID: String = {
        if let env = ProcessInfo.processInfo.environment["CALLY_GOOGLE_CLIENT_ID"], !env.isEmpty {
            return env
        }
        return "YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com"
    }()

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
