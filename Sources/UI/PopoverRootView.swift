import SwiftUI
import AppKit

struct PopoverRootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var syncManager: SyncManager

    var body: some View {
        Group {
            switch appState.authStatus {
            case .signedOut, .signingIn:
                SignInView()
            case .needsReconnect:
                ReconnectView()
            case .signedIn:
                EventListView()
            }
        }
        .frame(width: 320)
    }
}

struct EventListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var syncManager: SyncManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.isOffline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash").font(.caption)
                    Text("Offline — showing cached events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(sections, id: \.id) { section in
                        SectionHeader(title: section.title)
                        ForEach(section.events) { ev in
                            EventRow(event: ev)
                        }
                    }
                    if sections.isEmpty {
                        Text("No upcoming events")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 420)

            Divider()

            FooterView()
        }
    }

    var sections: [EventSection] {
        EventGrouping.group(events: appState.events, now: Date())
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

struct ReconnectView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Reconnect to Google")
                .font(.headline)
            Text("Your sign-in has expired or was revoked.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Reconnect") {
                Task { await SignInController.signIn(appState: appState) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 320)
    }
}

struct FooterView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            footerRow(label: "Open Google Calendar") {
                if let url = URL(string: "https://calendar.google.com") {
                    NSWorkspace.shared.open(url)
                }
            }
            footerRow(label: "Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                if #available(macOS 14, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            }
            footerRow(label: "Quit Cally") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    func footerRow(label: String, action: @escaping () -> Void) -> some View {
        HoverButton(action: action) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
    }
}

struct HoverButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            content()
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovered ? Color.accentColor.opacity(0.18) : Color.clear)
                        .padding(.horizontal, 8)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
