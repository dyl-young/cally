import SwiftUI
import AppKit

/// A single event row. Tapping/Enter opens the event in Google Calendar.
struct EventRow: View {
    let event: CalendarEvent
    let isFocused: Bool

    @Environment(\.popoverDismiss) private var dismiss

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color(event.calendarColor))
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))

            Text(formattedTime)
                .font(.system(.body, design: .default).monospacedDigit())
                .foregroundStyle(.primary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text(event.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight)
        .contentShape(Rectangle())
        .onTapGesture { invoke() }
    }

    @ViewBuilder
    private var highlight: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isFocused ? Color.accentColor.opacity(0.18) : Color.clear)
            .padding(.horizontal, 6)
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

    @Environment(\.popoverDismiss) private var dismiss

    var body: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 3)
            GoogleMeetIcon(size: 16)
            Text("Join Google Meet meeting")
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight)
        .contentShape(Rectangle())
        .onTapGesture { invoke() }
    }

    @ViewBuilder
    private var highlight: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isFocused ? Color.accentColor.opacity(0.18) : Color.clear)
            .padding(.horizontal, 6)
    }

    func invoke() {
        if let url = event.meetLink {
            NSWorkspace.shared.open(url)
        }
        dismiss()
    }
}
