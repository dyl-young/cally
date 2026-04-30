import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let syncManager: SyncManager
    private let statusItem: NSStatusItem
    private var titleTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var hotKey: GlobalHotKey?
    private var isMenuOpen = false
    private var pendingRebuild = false
    private let settingsController = SettingsWindowController()

    init(appState: AppState, syncManager: SyncManager) {
        self.appState = appState
        self.syncManager = syncManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageLeft
        }

        rebuildMenu()
        refreshTitle()

        appState.$events
            .merge(with: appState.$authStatus.map { _ in [] }.eraseToAnyPublisher())
            .merge(with: appState.$isOffline.map { _ in [] }.eraseToAnyPublisher())
            .sink { [weak self] _ in self?.scheduleRebuild() }
            .store(in: &cancellables)

        appState.$events
            .sink { [weak self] _ in self?.refreshTitle() }
            .store(in: &cancellables)

        scheduleTitleTimer()
        registerHotKey()
    }

    func stop() {
        titleTimer?.invalidate()
        titleTimer = nil
    }

    private func registerHotKey() {
        let modifiers = UInt32(cmdKey | controlKey)
        let keyCode = UInt32(kVK_ANSI_K)
        hotKey = GlobalHotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.openMenu()
        }
    }

    private func openMenu() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        button.performClick(nil)
    }

    // MARK: Menu rebuild

    private func scheduleRebuild() {
        if isMenuOpen {
            pendingRebuild = true
        } else {
            rebuildMenu()
        }
    }

    private func rebuildMenu() {
        let menu = MenuBuilder(
            appState: appState,
            onSignIn: { [weak self] in
                guard let self else { return }
                Task { await SignInController.signIn(appState: self.appState) }
            },
            onSignOut: { [weak self] in
                guard let self else { return }
                Task { await SignInController.signOut(appState: self.appState) }
            },
            onOpenEvent: { [weak self] ev in
                guard let self else { return }
                if let s = ev.htmlLink, let u = URL(string: s) { NSWorkspace.shared.open(u) }
                _ = self
            },
            onJoinMeet: { ev in
                if let url = ev.meetLink { NSWorkspace.shared.open(url) }
            },
            onOpenCalendarWeb: {
                if let u = URL(string: "https://calendar.google.com") { NSWorkspace.shared.open(u) }
            },
            onOpenSettings: { [weak self] in
                guard let self else { return }
                self.settingsController.show(appState: self.appState)
            }
        ).build()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        syncManager.setMenuOpen(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        syncManager.setMenuOpen(false)
        if pendingRebuild {
            pendingRebuild = false
            rebuildMenu()
        }
    }

    // MARK: Title

    private func scheduleTitleTimer() {
        titleTimer?.invalidate()
        let interval = TitleFormatter.tickInterval(events: appState.events)
        titleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshTitle()
                self?.scheduleTitleTimer()
            }
        }
    }

    private func refreshTitle() {
        guard let button = statusItem.button else { return }
        let title = TitleFormatter.format(events: appState.events)
        let target = TitleFormatter.pickTarget(events: appState.events)

        if let title, let target {
            button.image = makeBarImage(color: target.calendarColor)
            button.title = " " + title
            button.imagePosition = .imageLeft
        } else {
            let icon = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Cally")
            icon?.isTemplate = true
            button.image = icon
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    /// Renders the calendar-coloured vertical bar used as the status item icon when an event is
    /// in view. When nothing's upcoming we fall back to the `calendar` SF Symbol (in refreshTitle).
    private func makeBarImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 4, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 2, yRadius: 2).fill()
        image.unlockFocus()
        image.isTemplate = false
        image.accessibilityDescription = "Cally"
        return image
    }
}
