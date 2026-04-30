import SwiftUI
import AppKit

struct EventRow: View {
    let event: CalendarEvent
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color(event.calendarColor))
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))

                Text(formattedTime)
                    .font(.system(.body, design: .default).monospacedDigit())
                    .foregroundStyle(timeColor)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text(event.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(titleColor)

                Spacer(minLength: 4)

                if hovered, event.meetLink != nil {
                    Button("Join") {
                        joinMeeting()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)

            if event.meetLink != nil {
                HStack(spacing: 8) {
                    Spacer().frame(width: 3)
                    Image(systemName: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Join Google Meet meeting")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 14)
                .padding(.bottom, 4)
                .onTapGesture { joinMeeting() }
                .contentShape(Rectangle())
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovered ? Color.accentColor.opacity(0.10) : Color.clear)
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture {
            openInCalendar()
        }
    }

    var formattedTime: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: event.start)
    }

    var timeColor: Color {
        event.isInProgress ? .primary : .primary
    }

    var titleColor: Color {
        event.isInProgress ? .primary : .primary
    }

    func openInCalendar() {
        if let s = event.htmlLink, let u = URL(string: s) {
            NSWorkspace.shared.open(u)
        }
    }

    func joinMeeting() {
        if let url = event.meetLink {
            NSWorkspace.shared.open(url)
        }
    }
}
