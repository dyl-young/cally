import Foundation

enum TitleFormatter {
    static let visibilityThreshold: TimeInterval = 12 * 60 * 60
    static let titleMaxChars = 22

    /// Builds the menu bar title for the next/current event, or nil to hide.
    static func format(events: [CalendarEvent], now: Date = Date()) -> String? {
        guard let target = pickTarget(events: events, now: now) else { return nil }
        let truncated = truncate(target.title)

        if target.isInProgress {
            let remaining = target.end.timeIntervalSince(now)
            if remaining <= 0 { return nil }
            return "\(truncated) · \(formatDuration(remaining)) left"
        } else {
            let until = target.start.timeIntervalSince(now)
            if until <= 0 { return "\(truncated) · starting now" }
            if until <= 30 { return "\(truncated) · starting now" }
            if until > visibilityThreshold { return nil }
            return "\(truncated) · in \(formatDuration(until))"
        }
    }

    /// Tick interval — short when imminent.
    static func tickInterval(events: [CalendarEvent], now: Date = Date()) -> TimeInterval {
        guard let target = pickTarget(events: events, now: now) else { return 60 }
        let delta = target.isInProgress
            ? target.end.timeIntervalSince(now)
            : target.start.timeIntervalSince(now)
        return delta < 120 ? 10 : 30
    }

    static func pickTarget(events: [CalendarEvent], now: Date = Date()) -> CalendarEvent? {
        if let inProgress = events.first(where: { $0.isInProgress }) {
            return inProgress
        }
        return events.first { $0.start > now }
    }

    static func truncate(_ s: String) -> String {
        s.count > titleMaxChars ? String(s.prefix(titleMaxChars - 1)) + "…" : s
    }

    /// "1h 52m", "19m", "0m"
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let mins = max(0, total / 60)
        let h = mins / 60
        let m = mins % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
