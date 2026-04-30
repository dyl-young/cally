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

/// One selectable item in the popover. Drives keyboard navigation order and Enter activation.
private struct PopoverItem: Identifiable {
    let id: String
    let kind: Kind
    let action: () -> Void

    enum Kind {
        case event(CalendarEvent)
        case meet(CalendarEvent)
        case footer(label: String)
        case settings
        case quit
    }
}

struct EventListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.popoverDismiss) private var dismiss

    @FocusState private var focusedID: String?

    var body: some View {
        let items = buildItems()
        let ids = items.map(\.id)

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
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.id) { section in
                        SectionHeader(title: section.title)
                        ForEach(section.events) { ev in
                            EventRow(event: ev, isFocused: focusedID == itemID(.event, ev.id))
                                .focusable()
                                .focused($focusedID, equals: itemID(.event, ev.id))
                            if ev.meetLink != nil {
                                MeetJoinRow(event: ev, isFocused: focusedID == itemID(.meet, ev.id))
                                    .focusable()
                                    .focused($focusedID, equals: itemID(.meet, ev.id))
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
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 420)

            Divider()

            FooterView(focusedID: $focusedID)
        }
        .onKeyPress(.upArrow) { moveFocus(-1, in: ids); return .handled }
        .onKeyPress(.downArrow) { moveFocus(1, in: ids); return .handled }
        .onKeyPress(.return) {
            if let id = focusedID, let item = items.first(where: { $0.id == id }) {
                item.action()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .task {
            if focusedID == nil { focusedID = ids.first }
        }
        .onChange(of: ids) { _, newIDs in
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

    private func buildItems() -> [PopoverItem] {
        var items: [PopoverItem] = []
        for section in sections {
            for ev in section.events {
                items.append(PopoverItem(
                    id: itemID(.event, ev.id),
                    kind: .event(ev),
                    action: { openEvent(ev); dismiss() }
                ))
                if ev.meetLink != nil {
                    items.append(PopoverItem(
                        id: itemID(.meet, ev.id),
                        kind: .meet(ev),
                        action: { joinMeet(ev); dismiss() }
                    ))
                }
            }
        }
        items.append(PopoverItem(id: "footer.calendar", kind: .footer(label: "Open Google Calendar"), action: openCalendarWeb))
        items.append(PopoverItem(id: "footer.settings", kind: .settings, action: {}))
        items.append(PopoverItem(id: "footer.quit", kind: .quit, action: { NSApp.terminate(nil) }))
        return items
    }

    private enum ItemKind { case event, meet }
    private func itemID(_ kind: ItemKind, _ eventID: String) -> String {
        "\(kind == .event ? "ev" : "meet").\(eventID)"
    }

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
    private func openCalendarWeb() {
        if let u = URL(string: "https://calendar.google.com") { NSWorkspace.shared.open(u) }
        dismiss()
    }
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
    @FocusState.Binding var focusedID: String?

    @Environment(\.popoverDismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            FooterRow(
                id: "footer.calendar",
                label: "Open Google Calendar",
                isFocused: focusedID == "footer.calendar",
                action: {
                    if let u = URL(string: "https://calendar.google.com") { NSWorkspace.shared.open(u) }
                    dismiss()
                }
            )
            .focusable()
            .focused($focusedID, equals: "footer.calendar")

            SettingsLinkRow(isFocused: focusedID == "footer.settings", onActivate: dismiss)
                .focusable()
                .focused($focusedID, equals: "footer.settings")

            FooterRow(
                id: "footer.quit",
                label: "Quit Cally",
                isFocused: focusedID == "footer.quit",
                action: { NSApp.terminate(nil) }
            )
            .focusable()
            .focused($focusedID, equals: "footer.quit")
        }
        .padding(.vertical, 4)
    }
}

struct FooterRow: View {
    let id: String
    let label: String
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Text(label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFocused ? Color.accentColor.opacity(0.18) : Color.clear)
                    .padding(.horizontal, 8)
            )
            .contentShape(Rectangle())
            .onTapGesture { action() }
    }
}

/// Wraps SettingsLink so it gets the same look as other footer rows. SettingsLink is itself a
/// Button, so we make it visually neutral and let the surrounding `.focused()` modifier drive
/// keyboard navigation and Enter activation.
struct SettingsLinkRow: View {
    let isFocused: Bool
    let onActivate: () -> Void

    var body: some View {
        SettingsLink {
            Text("Settings…")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isFocused ? Color.accentColor.opacity(0.18) : Color.clear)
                        .padding(.horizontal, 8)
                )
                .contentShape(Rectangle())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { onActivate() })
    }
}
