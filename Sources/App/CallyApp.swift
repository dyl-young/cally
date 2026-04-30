import SwiftUI

@main
struct CallyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Placeholder scene — the App protocol requires at least one Scene. Settings is hosted
        // via SettingsWindowController in AppKit so we never actually invoke this scene.
        Settings { EmptyView() }
    }
}
