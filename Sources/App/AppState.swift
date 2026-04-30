import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var accounts: [GoogleAccount] = []
    @Published var accountsNeedingReconnect: Set<String> = []
    @Published var addingAccount: Bool = false
    @Published var addAccountError: String?

    @Published var events: [CalendarEvent] = []
    @Published var lastSyncDate: Date?
    @Published var lastSyncError: String?
    @Published var isOffline: Bool = false

    @Published var notificationsEnabled: Bool = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    /// Full list of every linked account's Google calendars. `accountID` on each is set when fetched.
    @Published var calendars: [GoogleCalendarSummary] = []

    /// Calendars the user has selected to display events from. Persisted.
    @Published var selectedCalendars: Set<CalendarRef> = AppState.loadSelectedCalendars() {
        didSet { AppState.saveSelectedCalendars(selectedCalendars) }
    }

    init() {
        accounts = GoogleAccount.loadAll()
        AppState.migrateLegacySelectedCalendarIDsIfNeeded(primaryAccountID: accounts.first?.id)
        selectedCalendars = AppState.loadSelectedCalendars()
    }

    var isSignedIn: Bool { !accounts.isEmpty }

    func calendarsForAccount(_ accountID: String) -> [GoogleCalendarSummary] {
        calendars.filter { $0.accountID == accountID }
    }

    // MARK: Persistence

    private static let selectedCalendarsKey = "selectedCalendars"

    private static func loadSelectedCalendars() -> Set<CalendarRef> {
        guard let data = UserDefaults.standard.data(forKey: selectedCalendarsKey),
              let array = try? JSONDecoder().decode([CalendarRef].self, from: data) else {
            return []
        }
        return Set(array)
    }

    private static func saveSelectedCalendars(_ refs: Set<CalendarRef>) {
        if let data = try? JSONEncoder().encode(Array(refs)) {
            UserDefaults.standard.set(data, forKey: selectedCalendarsKey)
        }
    }

    /// Single-account installs persisted `selectedCalendarIDs: [String]`. Migrate those to refs
    /// scoped under the previously-primary account.
    private static func migrateLegacySelectedCalendarIDsIfNeeded(primaryAccountID: String?) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: selectedCalendarsKey) == nil,
              let legacy = defaults.stringArray(forKey: "selectedCalendarIDs"),
              !legacy.isEmpty,
              let accountID = primaryAccountID else { return }
        let refs = legacy.map { CalendarRef(accountID: accountID, calendarID: $0) }
        if let data = try? JSONEncoder().encode(refs) {
            defaults.set(data, forKey: selectedCalendarsKey)
        }
        defaults.removeObject(forKey: "selectedCalendarIDs")
    }
}
