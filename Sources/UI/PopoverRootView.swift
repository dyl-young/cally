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
        .frame(width: 300)
        .background(VisualEffectView(material: .menu))
    }
}

struct EventListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.popoverDismiss) private var dismiss

    @FocusState private var focusedID: String?

    var body: some View {
        let ordered = orderedItemIDs

        VStack(alignment: .leading, spacing: 0) {
            if appState.isOffline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash").font(.caption)
                    Text("Offline — showing cached events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.id) { section in
                        SectionHeader(title: section.title)
                        ForEach(section.events) { ev in
                            EventRow(event: ev, isFocused: focusedID == eventID(ev))
                                .focusable()
                                .focused($focusedID, equals: eventID(ev))
                            if ev.meetLink != nil {
                                MeetJoinRow(event: ev, isFocused: focusedID == meetID(ev))
                                    .focusable()
                                    .focused($focusedID, equals: meetID(ev))
                            }
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
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 420)

            Divider()

            FooterView(focusedID: $focusedID)
        }
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveFocus(-1, in: ordered); return .handled }
        .onKeyPress(.downArrow) { moveFocus(1, in: ordered); return .handled }
        .onKeyPress(.return) {
            if let id = focusedID, let action = actions[id] {
                action()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onAppear { focusedID = ordered.first }
        .onChange(of: appState.popoverShowCount) { _, _ in
            focusedID = ordered.first
        }
        .onChange(of: ordered) { _, newIDs in
            if let current = focusedID, !newIDs.contains(current) {
                focusedID = newIDs.first
            } else if focusedID == nil {
                focusedID = newIDs.first
            }
        }
    }

    var sections: [EventSection] {
        EventGrouping.group(events: appState.events, now: Date())
    }

    private var orderedItemIDs: [String] {
        var ids: [String] = []
        for section in sections {
            for ev in section.events {
                ids.append(eventID(ev))
                if ev.meetLink != nil { ids.append(meetID(ev)) }
            }
        }
        ids.append(FooterID.calendar)
        ids.append(FooterID.settings)
        ids.append(FooterID.quit)
        return ids
    }

    private var actions: [String: () -> Void] {
        var dict: [String: () -> Void] = [:]
        for section in sections {
            for ev in section.events {
                dict[eventID(ev)] = { openEvent(ev); dismiss() }
                if ev.meetLink != nil {
                    dict[meetID(ev)] = { joinMeet(ev); dismiss() }
                }
            }
        }
        dict[FooterID.calendar] = {
            if let u = URL(string: "https://calendar.google.com") { NSWorkspace.shared.open(u) }
            dismiss()
        }
        // Settings is handled by SettingsLink itself; no action here.
        dict[FooterID.settings] = {}
        dict[FooterID.quit] = { NSApp.terminate(nil) }
        return dict
    }

    private func eventID(_ ev: CalendarEvent) -> String { "ev.\(ev.id)" }
    private func meetID(_ ev: CalendarEvent) -> String { "meet.\(ev.id)" }

    private func moveFocus(_ delta: Int, in ids: [String]) {
        guard !ids.isEmpty else { return }
        let current = focusedID.flatMap { ids.firstIndex(of: $0) } ?? -1
        let next = (current + delta).clamped(to: 0...(ids.count - 1))
        focusedID = ids[next]
    }

    private func openEvent(_ ev: CalendarEvent) {
        if let s = ev.htmlLink, let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
    private func joinMeet(_ ev: CalendarEvent) {
        if let url = ev.meetLink { NSWorkspace.shared.open(url) }
    }
}

enum FooterID {
    static let calendar = "footer.calendar"
    static let settings = "footer.settings"
    static let quit = "footer.quit"
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
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
        .frame(width: 300)
    }
}

struct FooterView: View {
    @FocusState.Binding var focusedID: String?

    @Environment(\.popoverDismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            FooterRow(
                label: "Open Google Calendar",
                isFocused: focusedID == FooterID.calendar,
                action: {
                    if let u = URL(string: "https://calendar.google.com") { NSWorkspace.shared.open(u) }
                    dismiss()
                }
            )
            .focusable()
            .focused($focusedID, equals: FooterID.calendar)

            SettingsLinkRow(
                isFocused: focusedID == FooterID.settings,
                onActivate: dismiss
            )
            .focusable()
            .focused($focusedID, equals: FooterID.settings)

            FooterRow(
                label: "Quit Cally",
                isFocused: focusedID == FooterID.quit,
                action: { NSApp.terminate(nil) }
            )
            .focusable()
            .focused($focusedID, equals: FooterID.quit)
        }
        .padding(.vertical, 4)
    }
}

struct FooterRow: View {
    let label: String
    let isFocused: Bool
    let action: () -> Void

    @State private var isHovered = false
    private var isHighlighted: Bool { isFocused || isHovered }

    var body: some View {
        Text(label)
            .foregroundStyle(isHighlighted ? Color(NSColor.selectedMenuItemTextColor) : Color(NSColor.labelColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(isHighlighted ? Color(NSColor.selectedContentBackgroundColor) : Color.clear)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture { action() }
    }
}

struct SettingsLinkRow: View {
    let isFocused: Bool
    let onActivate: () -> Void

    @State private var isHovered = false
    private var isHighlighted: Bool { isFocused || isHovered }

    var body: some View {
        SettingsLink {
            Text("Settings…")
                .foregroundStyle(isHighlighted ? Color(NSColor.selectedMenuItemTextColor) : Color(NSColor.labelColor))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(isHighlighted ? Color(NSColor.selectedContentBackgroundColor) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(TapGesture().onEnded { onActivate() })
    }
}
