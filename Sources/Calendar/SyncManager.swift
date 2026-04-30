import Foundation
import AppKit
import Combine

@MainActor
final class SyncManager: ObservableObject {
    private let appState: AppState
    private let client = CalendarClient()
    private var timer: Timer?
    private var syncTokens: [CalendarRef: String] = [:]
    private var eventsPerCalendar: [CalendarRef: [CalendarEvent]] = [:]
    private var calendarsLoadedFor: Set<String> = []
    private var isMenuOpen: Bool = false
    private var inFlight: Bool = false
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        if let cached = EventCache.load() {
            syncTokens = cached.syncTokens
            for ev in cached.events {
                eventsPerCalendar[ev.calendarRef, default: []].append(ev)
            }
            appState.events = filtered(cached.events.sorted { $0.start < $1.start })
            appState.lastSyncDate = cached.lastSync
        }

        // Refresh whenever the linked-account set changes (sign-in adds, sign-out removes).
        appState.$accounts
            .removeDuplicates(by: { lhs, rhs in
                lhs.map(\.id) == rhs.map(\.id)
            })
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in await self.refreshNow() }
            }
            .store(in: &cancellables)

        appState.$selectedCalendars
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in await self.refreshNow() }
            }
            .store(in: &cancellables)
    }

    func start() async {
        guard !appState.accounts.isEmpty else { return }
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
        guard !appState.accounts.isEmpty, !inFlight else {
            // No accounts — wipe stale state.
            if appState.accounts.isEmpty {
                eventsPerCalendar.removeAll()
                syncTokens.removeAll()
                appState.events = []
                appState.calendars = []
                calendarsLoadedFor.removeAll()
                EventCache.clear()
            }
            return
        }
        inFlight = true
        defer { inFlight = false }

        // Refresh calendar lists for each account.
        var allCalendars: [GoogleCalendarSummary] = []
        for account in appState.accounts {
            do {
                let cals = try await loadCalendars(for: account)
                allCalendars.append(contentsOf: cals)
                appState.accountsNeedingReconnect.remove(account.id)
            } catch {
                if case AuthError.tokenExchangeFailed = error {
                    appState.accountsNeedingReconnect.insert(account.id)
                } else if (error as NSError).domain == NSURLErrorDomain {
                    appState.isOffline = true
                } else {
                    appState.lastSyncError = error.localizedDescription
                }
            }
        }
        appState.calendars = sortedCalendars(allCalendars)

        // First-run-per-account default: if nothing's selected for an account yet, select its primary calendar.
        for account in appState.accounts {
            let hasAnySelectedForAccount = appState.selectedCalendars.contains { $0.accountID == account.id }
            if !hasAnySelectedForAccount,
               let primary = allCalendars.first(where: { $0.accountID == account.id && $0.primary == true }) {
                var s = appState.selectedCalendars
                s.insert(primary.ref)
                appState.selectedCalendars = s
            }
        }

        // Drop state for refs that aren't selected anymore.
        for ref in Array(eventsPerCalendar.keys) where !appState.selectedCalendars.contains(ref) {
            eventsPerCalendar.removeValue(forKey: ref)
            syncTokens.removeValue(forKey: ref)
        }

        // Fetch each selected calendar.
        let accountsByID: [String: GoogleAccount] = Dictionary(uniqueKeysWithValues: appState.accounts.map { ($0.id, $0) })
        var hadError = false
        for ref in appState.selectedCalendars {
            guard let account = accountsByID[ref.accountID] else { continue }
            do {
                try await fetchCalendar(ref: ref, account: account)
            } catch CalendarClientError.syncTokenInvalid {
                continue // already retried inside fetchCalendar
            } catch {
                hadError = true
                if case AuthError.tokenExchangeFailed = error {
                    appState.accountsNeedingReconnect.insert(account.id)
                } else if (error as NSError).domain == NSURLErrorDomain {
                    appState.isOffline = true
                } else {
                    appState.lastSyncError = error.localizedDescription
                }
            }
        }

        publishAndCache()
        if !hadError {
            appState.lastSyncError = nil
            appState.isOffline = false
        }
    }

    private func loadCalendars(for account: GoogleAccount) async throws -> [GoogleCalendarSummary] {
        let cals = try await client.listCalendars(account: account)
        calendarsLoadedFor.insert(account.id)
        return cals
    }

    private func sortedCalendars(_ cals: [GoogleCalendarSummary]) -> [GoogleCalendarSummary] {
        cals.sorted { lhs, rhs in
            if lhs.accountID != rhs.accountID {
                return lhs.accountID < rhs.accountID
            }
            if lhs.primary == true && rhs.primary != true { return true }
            if rhs.primary == true && lhs.primary != true { return false }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func fetchCalendar(ref: CalendarRef, account: GoogleAccount) async throws {
        let timeMin = Calendar.current.startOfDay(for: Date())
        let timeMax = Calendar.current.date(byAdding: .day, value: 7, to: timeMin)!
        let isPrimary = appState.calendars.first(where: { $0.ref == ref })?.primary == true

        let token = syncTokens[ref]
        var pageToken: String? = nil
        var working: [CalendarEvent] = eventsPerCalendar[ref] ?? []
        var deletedIDs: Set<String> = []
        var newSyncToken: String? = nil

        repeat {
            let page: EventListPage
            do {
                page = try await client.listEvents(
                    account: account,
                    calendarID: ref.calendarID,
                    isPrimaryCalendar: isPrimary,
                    timeMin: timeMin,
                    timeMax: timeMax,
                    syncToken: token,
                    pageToken: pageToken
                )
            } catch CalendarClientError.syncTokenInvalid {
                syncTokens.removeValue(forKey: ref)
                eventsPerCalendar.removeValue(forKey: ref)
                try await fetchCalendar(ref: ref, account: account)
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

        if token == nil {
            working = working.filter { $0.end >= timeMin && $0.start <= timeMax }
        }
        if !deletedIDs.isEmpty {
            working.removeAll { deletedIDs.contains($0.id) }
        }
        working.removeAll { $0.end < Date() && !$0.isInProgress }

        eventsPerCalendar[ref] = working
        if let t = newSyncToken { syncTokens[ref] = t }
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
