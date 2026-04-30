import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    enum AuthStatus {
        case signedOut
        case signingIn
        case signedIn(account: GoogleAccount)
        case needsReconnect
    }

    @Published var authStatus: AuthStatus = .signedOut
    @Published var events: [CalendarEvent] = []
    @Published var lastSyncDate: Date?
    @Published var lastSyncError: String?
    @Published var isOffline: Bool = false
    @Published var notificationsEnabled: Bool = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    init() {
        if let account = GoogleAccount.loadFromKeychain() {
            authStatus = .signedIn(account: account)
        }
    }

    var currentAccount: GoogleAccount? {
        if case .signedIn(let account) = authStatus { return account }
        return nil
    }
}
