import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let appState: AppState
    private let syncManager: SyncManager
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var titleTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var hotKey: GlobalHotKey?

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
                .environment(\.popoverDismiss, { [weak self] in self?.popover.performClose(nil) })
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
        registerHotKey()
    }

    private func registerHotKey() {
        // ⌘⌃K — open/close popover from anywhere
        let modifiers = UInt32(cmdKey | controlKey)
        let keyCode = UInt32(kVK_ANSI_K)
        hotKey = GlobalHotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.togglePopover()
        }
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
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        syncManager.setPopoverOpen(true)
        appState.popoverShowCount += 1
        // Make the SwiftUI hosting view first responder so @FocusState bindings can paint focus.
        if let host = popover.contentViewController?.view {
            DispatchQueue.main.async {
                host.window?.makeFirstResponder(host)
            }
        }
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
