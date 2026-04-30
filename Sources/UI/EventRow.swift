import SwiftUI
import AppKit

/// A single event row. Tapping/Enter opens the event in Google Calendar.
struct EventRow: View {
    let event: CalendarEvent
    let isFocused: Bool

    @State private var isHovered = false
    @Environment(\.popoverDismiss) private var dismiss

    private var isHighlighted: Bool { isFocused || isHovered }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(isHighlighted ? Color.white.opacity(0.9) : Color(event.calendarColor))
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))

            Text(formattedTime)
                .font(.system(.body, design: .default).monospacedDigit())

            Text("·")
                .opacity(isHighlighted ? 0.7 : 0.35)

            Text(event.title)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)
        }
        .foregroundStyle(isHighlighted ? Color(NSColor.selectedMenuItemTextColor) : Color(NSColor.labelColor))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { invoke() }
    }

    @ViewBuilder
    private var highlight: some View {
        if isHighlighted {
            Color(NSColor.selectedContentBackgroundColor)
        } else {
            Color.clear
        }
    }

    private var formattedTime: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: event.start)
    }

    func invoke() {
        if let s = event.htmlLink, let u = URL(string: s) {
            NSWorkspace.shared.open(u)
        }
        dismiss()
    }
}

/// Sub-row "Join Google Meet meeting" — only rendered when the parent event has a Meet link.
struct MeetJoinRow: View {
    let event: CalendarEvent
    let isFocused: Bool

    @State private var isHovered = false
    @Environment(\.popoverDismiss) private var dismiss

    private var isHighlighted: Bool { isFocused || isHovered }

    var body: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 3)
            GoogleMeetIcon(size: 14)
            Text("Join Google Meet meeting")
            Spacer(minLength: 4)
        }
        .foregroundStyle(isHighlighted ? Color(NSColor.selectedMenuItemTextColor) : Color(NSColor.labelColor))
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHighlighted ? Color(NSColor.selectedContentBackgroundColor) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { invoke() }
    }

    func invoke() {
        if let url = event.meetLink {
            NSWorkspace.shared.open(url)
        }
        dismiss()
    }
}
