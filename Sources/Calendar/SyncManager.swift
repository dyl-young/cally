import Foundation
import AppKit
import Combine

@MainActor
final class SyncManager: ObservableObject {
    private let appState: AppState
    private let client = CalendarClient()
    private var timer: Timer?
    private var syncToken: String?
    private var calendarID: String = "primary"
    private var isPopoverOpen: Bool = false
    private var inFlight: Bool = false
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        if let cached = EventCache.load() {
            appState.events = filtered(cached.events)
            syncToken = cached.syncToken
            appState.lastSyncDate = cached.lastSync
        }

        appState.$authStatus
            .removeDuplicates(by: Self.statusEqual)
            .sink { [weak self] status in
                guard let self else { return }
                if case .signedIn = status {
                    self.calendarID = "primary"
                    self.syncToken = nil
                    Task { @MainActor in await self.refreshNow() }
                } else if case .signedOut = status {
                    self.stop()
                    self.appState.events = []
                }
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

    func setPopoverOpen(_ open: Bool) {
        isPopoverOpen = open
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
            if calendarID == "primary" || calendarID.isEmpty {
                calendarID = try await client.primaryCalendarID(account: account)
            }
            try await fetchAll(account: account)
            appState.lastSyncError = nil
            appState.isOffline = false
        } catch CalendarClientError.syncTokenInvalid {
            syncToken = nil
            EventCache.clear()
            await refreshNow()
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

    private func fetchAll(account: GoogleAccount) async throws {
        let timeMin = Calendar.current.startOfDay(for: Date())
        let timeMax = Calendar.current.date(byAdding: .day, value: 7, to: timeMin)!

        var allEvents: [CalendarEvent] = appState.events
        var deletedIDs: Set<String> = []
        var pageToken: String? = nil
        var newSyncToken: String? = nil

        repeat {
            let page = try await client.listEvents(
                account: account,
                calendarID: calendarID,
                timeMin: timeMin,
                timeMax: timeMax,
                syncToken: syncToken,
                pageToken: pageToken
            )
            for ev in page.events {
                if let idx = allEvents.firstIndex(where: { $0.id == ev.id }) {
                    allEvents[idx] = ev
                } else {
                    allEvents.append(ev)
                }
            }
            deletedIDs.formUnion(page.deletedIDs)
            pageToken = page.nextPageToken
            if let t = page.nextSyncToken { newSyncToken = t }
        } while pageToken != nil

        // If this was a full sync (no syncToken), replace the entire list
        if syncToken == nil {
            allEvents = allEvents.filter { ev in
                ev.end >= timeMin && ev.start <= timeMax
            }
        }
        if !deletedIDs.isEmpty {
            allEvents.removeAll { deletedIDs.contains($0.id) }
        }
        // Drop events that fell out of window
        allEvents.removeAll { $0.end < Date() && !$0.isInProgress }

        allEvents.sort { $0.start < $1.start }
        if let t = newSyncToken { syncToken = t }

        appState.events = filtered(allEvents)
        appState.lastSyncDate = Date()
        EventCache.save(.init(events: allEvents, syncToken: syncToken, lastSync: Date()))
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
        let interval: TimeInterval = isPopoverOpen ? 60 : 300
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshNow() }
        }
    }
}
