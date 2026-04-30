import Foundation
import AppKit
import Combine

@MainActor
final class SyncManager: ObservableObject {
    private let appState: AppState
    private let client = CalendarClient()
    private var timer: Timer?
    private var syncTokens: [String: String] = [:]
    private var eventsPerCalendar: [String: [CalendarEvent]] = [:]
    private var calendarsLoaded = false
    private var isMenuOpen: Bool = false
    private var inFlight: Bool = false
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        if let cached = EventCache.load() {
            syncTokens = cached.syncTokens
            for ev in cached.events {
                eventsPerCalendar[ev.calendarId, default: []].append(ev)
            }
            appState.events = filtered(cached.events.sorted { $0.start < $1.start })
            appState.lastSyncDate = cached.lastSync
        }

        appState.$authStatus
            .removeDuplicates(by: Self.statusEqual)
            .sink { [weak self] status in
                guard let self else { return }
                if case .signedIn = status {
                    self.calendarsLoaded = false
                    self.syncTokens.removeAll()
                    self.eventsPerCalendar.removeAll()
                    Task { @MainActor in await self.refreshNow() }
                } else if case .signedOut = status {
                    self.stop()
                    self.appState.events = []
                    self.appState.calendars = []
                    self.calendarsLoaded = false
                    self.syncTokens.removeAll()
                    self.eventsPerCalendar.removeAll()
                }
            }
            .store(in: &cancellables)

        appState.$selectedCalendarIDs
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in await self.refreshNow() }
            }
            .store(in: &cancellables)
    }

    private static func statusEqual(_ a: AppState.AuthStatus, _ b: AppState.AuthStatus) -> Bool {
        switch (a, b) {
        case (.signedOut, .signedOut), (.signingIn, .signingIn), (.needsReconnect, .needsReconnect):
            return true
        case (.signedIn(let x), .signedIn(let y)):
            return x.id == y.id
        default:
            return false
        }
    }

    func start() async {
        guard appState.currentAccount != nil else { return }
        scheduleTimer()
        await refreshNow()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setMenuOpen(_ open: Bool) {
        isMenuOpen = open
        if open {
            Task { await refreshNow() }
        }
        scheduleTimer()
    }

    func refreshNow() async {
        guard let account = appState.currentAccount, !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        do {
            try await loadCalendarsIfNeeded(account: account)

            // Drop state for calendars no longer selected.
            for calID in Array(eventsPerCalendar.keys) where !appState.selectedCalendarIDs.contains(calID) {
                eventsPerCalendar.removeValue(forKey: calID)
                syncTokens.removeValue(forKey: calID)
            }

            // Fetch each selected calendar.
            for calID in appState.selectedCalendarIDs {
                try await fetchCalendar(calID, account: account)
            }

            publishAndCache()
            appState.lastSyncError = nil
            appState.isOffline = false
        } catch {
            if (error as NSError).domain == NSURLErrorDomain {
                appState.isOffline = true
            } else {
                appState.lastSyncError = error.localizedDescription
            }
            if case AuthError.tokenExchangeFailed = error {
                appState.authStatus = .needsReconnect
            }
        }
    }

    private func loadCalendarsIfNeeded(account: GoogleAccount) async throws {
        guard !calendarsLoaded || appState.calendars.isEmpty else { return }
        let cals = try await client.listCalendars(account: account)
        appState.calendars = cals.sorted { lhs, rhs in
            // Primary first, then alphabetical.
            if lhs.primary == true && rhs.primary != true { return true }
            if rhs.primary == true && lhs.primary != true { return false }
            return lhs.summary.localizedCaseInsensitiveCompare(rhs.summary) == .orderedAscending
        }
        if appState.selectedCalendarIDs.isEmpty {
            if let primary = cals.first(where: { $0.primary == true }) {
                appState.selectedCalendarIDs = [primary.id]
            }
        }
        calendarsLoaded = true
    }

    private func fetchCalendar(_ calendarID: String, account: GoogleAccount) async throws {
        let timeMin = Calendar.current.startOfDay(for: Date())
        let timeMax = Calendar.current.date(byAdding: .day, value: 7, to: timeMin)!

        let token = syncTokens[calendarID]
        var pageToken: String? = nil
        var working: [CalendarEvent] = eventsPerCalendar[calendarID] ?? []
        var deletedIDs: Set<String> = []
        var newSyncToken: String? = nil

        repeat {
            let page: EventListPage
            do {
                page = try await client.listEvents(
                    account: account,
                    calendarID: calendarID,
                    timeMin: timeMin,
                    timeMax: timeMax,
                    syncToken: token,
                    pageToken: pageToken
                )
            } catch CalendarClientError.syncTokenInvalid {
                syncTokens.removeValue(forKey: calendarID)
                eventsPerCalendar.removeValue(forKey: calendarID)
                try await fetchCalendar(calendarID, account: account)
                return
            }

            for ev in page.events {
                if let idx = working.firstIndex(where: { $0.id == ev.id }) {
                    working[idx] = ev
                } else {
                    working.append(ev)
                }
            }
            deletedIDs.formUnion(page.deletedIDs)
            pageToken = page.nextPageToken
            if let t = page.nextSyncToken { newSyncToken = t }
        } while pageToken != nil

        // Full sync (no prior token) — clamp to the requested window.
        if token == nil {
            working = working.filter { $0.end >= timeMin && $0.start <= timeMax }
        }
        if !deletedIDs.isEmpty {
            working.removeAll { deletedIDs.contains($0.id) }
        }
        // Drop fully-past events.
        working.removeAll { $0.end < Date() && !$0.isInProgress }

        eventsPerCalendar[calendarID] = working
        if let t = newSyncToken { syncTokens[calendarID] = t }
    }

    private func publishAndCache() {
        let all = eventsPerCalendar.values.flatMap { $0 }.sorted { $0.start < $1.start }
        appState.events = filtered(all)
        appState.lastSyncDate = Date()
        EventCache.save(.init(events: all, syncTokens: syncTokens, lastSync: Date()))
    }

    private func filtered(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.filter { ev in
            if ev.myResponseStatus == "declined" { return false }
            if ev.isAllDay { return false }
            return true
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval: TimeInterval = isMenuOpen ? 60 : 300
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshNow() }
        }
    }
}
