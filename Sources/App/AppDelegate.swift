import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState = AppState()
    private var menuBarController: MenuBarController!
    private var syncManager: SyncManager!
    private var notifier: MeetingNotifier!
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        syncManager = SyncManager(appState: appState)
        notifier = MeetingNotifier(appState: appState)
        menuBarController = MenuBarController(appState: appState, syncManager: syncManager)

        Task { await syncManager.start() }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.syncManager.refreshNow() }
        }

        UNUserNotificationCenter.current().delegate = notifier
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
