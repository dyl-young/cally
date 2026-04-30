import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let appState: AppState
    private let syncManager: SyncManager
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var titleTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState, syncManager: SyncManager) {
        self.appState = appState
        self.syncManager = syncManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView()
                .environmentObject(appState)
                .environmentObject(syncManager)
        )

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Cally")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeft
            button.action = #selector(togglePopover)
            button.target = self
        }

        appState.$events
            .sink { [weak self] _ in self?.refreshTitle() }
            .store(in: &cancellables)

        scheduleTitleTimer()
    }

    func stop() {
        titleTimer?.invalidate()
        titleTimer = nil
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        syncManager.setPopoverOpen(true)
    }

    func popoverDidClose(_ notification: Notification) {
        syncManager.setPopoverOpen(false)
    }

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
        let title = TitleFormatter.format(events: appState.events)
        guard let button = statusItem.button else { return }
        if let title {
            button.title = " " + title
            button.imagePosition = .imageLeft
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }
}
