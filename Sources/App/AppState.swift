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

    /// Full list of the user's Google calendars, refreshed on sign-in / sync.
    @Published var calendars: [GoogleCalendarSummary] = []

    /// Calendar IDs the user has selected to display events from. Persisted.
    @Published var selectedCalendarIDs: Set<String> = {
        let stored = UserDefaults.standard.stringArray(forKey: "selectedCalendarIDs") ?? []
        return Set(stored)
    }() {
        didSet {
            UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: "selectedCalendarIDs")
        }
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
