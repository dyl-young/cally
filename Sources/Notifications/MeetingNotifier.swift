import Foundation
import UserNotifications
import AppKit
import Combine

@MainActor
final class MeetingNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let appState: AppState
    private var scheduledIDs: Set<String> = []
    private var cancellables = Set<AnyCancellable>()
    private var hasRequestedAuth = false

    init(appState: AppState) {
        self.appState = appState
        super.init()

        appState.$events
            .sink { [weak self] events in self?.reschedule(events: events) }
            .store(in: &cancellables)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let urlStr = userInfo["meetURL"] as? String
        guard actionID == "JOIN" || actionID == UNNotificationDefaultActionIdentifier,
              let s = urlStr, let url = URL(string: s) else { return }
        await MainActor.run { NSWorkspace.shared.open(url) }
    }

    private func requestAuthIfNeeded() async {
        guard !hasRequestedAuth else { return }
        hasRequestedAuth = true
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Best-effort
        }
        let joinAction = UNNotificationAction(
            identifier: "JOIN",
            title: "Join",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "MEETING",
            actions: [joinAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    private func reschedule(events: [CalendarEvent]) {
        Task { await self.rescheduleAsync(events: events) }
    }

    private func rescheduleAsync(events: [CalendarEvent]) async {
        guard appState.notificationsEnabled else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            scheduledIDs.removeAll()
            return
        }
        await requestAuthIfNeeded()

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        scheduledIDs.removeAll()

        let now = Date()
        for ev in events {
            guard ev.isAttending else { continue }
            guard let meetLink = ev.meetLink else { continue }
            let triggerDate = ev.start.addingTimeInterval(-60)
            guard triggerDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = ev.title
            content.body = "Starting in 1 minute"
            content.sound = .default
            content.categoryIdentifier = "MEETING"
            content.userInfo = ["meetURL": meetLink.absoluteString]

            let interval = triggerDate.timeIntervalSince(now)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
            let req = UNNotificationRequest(identifier: ev.id, content: content, trigger: trigger)
            do {
                try await center.add(req)
                scheduledIDs.insert(ev.id)
            } catch {
                // Skip silently
            }
        }
    }
}
