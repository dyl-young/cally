import AppKit
import SwiftUI

/// Lazily-created NSWindow that hosts `SettingsView`. We manage this directly instead of using
/// SwiftUI's `Settings` scene because the latter requires `SettingsLink` to open from macOS 14+,
/// which only exists in SwiftUI views — and our menu lives in AppKit (NSMenu).
@MainActor
final class SettingsWindowController {
    private weak var appState: AppState?
    private var window: NSWindow?

    func show(appState: AppState) {
        self.appState = appState

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsView().environmentObject(appState)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Cally Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
