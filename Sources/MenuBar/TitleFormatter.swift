import Foundation

enum TitleFormatter {
    static let visibilityThreshold: TimeInterval = 12 * 60 * 60
    static let titleMaxChars = 22
    /// During the first N seconds of a meeting, the title reads "now" instead of "X left".
    static let nowWindow: TimeInterval = 5 * 60

    /// Builds the menu bar title for the next/current event, or nil to hide.
    static func format(events: [CalendarEvent], now: Date = Date()) -> String? {
        guard let target = pickTarget(events: events, now: now) else { return nil }
        let conflictSuffix = makeConflictSuffix(target: target, events: events, now: now)
        let truncated = responsePrefix(for: target) + truncate(target.title) + conflictSuffix

        if target.isInProgress {
            let remaining = target.end.timeIntervalSince(now)
            if remaining <= 0 { return nil }
            let elapsed = now.timeIntervalSince(target.start)
            if elapsed >= 0 && elapsed < nowWindow {
                return "\(truncated) · now"
            }
            return "\(truncated) · \(formatDuration(remaining)) left"
        } else {
            let until = target.start.timeIntervalSince(now)
            if until <= 0 { return "\(truncated) · now" }
            if until <= 30 { return "\(truncated) · now" }
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

    /// Selects the event the menu bar should announce. Prefers the in-progress event; falls back to
    /// the next future event. When multiple events tie at the same start (or are simultaneously in
    /// progress), uses a stable tiebreaker so the title doesn't flicker between events on each refresh.
    static func pickTarget(events: [CalendarEvent], now: Date = Date()) -> CalendarEvent? {
        let active = events.filter { $0.myResponseStatus != "declined" }
        let inProgress = active.filter { $0.isInProgress }
        if !inProgress.isEmpty {
            return chooseStable(from: inProgress)
        }
        let future = active.filter { $0.start > now }
        guard let earliest = future.min(by: { $0.start < $1.start }) else { return nil }
        let tied = future.filter { $0.start == earliest.start }
        return chooseStable(from: tied)
    }

    private static func responsePrefix(for event: CalendarEvent) -> String {
        switch event.myResponseStatus {
        case "needsAction": return "? "
        case "tentative": return "?? "
        default: return ""
        }
    }

    /// Tiebreaker: primary calendar > shorter event > alphabetical.
    private static func chooseStable(from events: [CalendarEvent]) -> CalendarEvent? {
        events.min { lhs, rhs in
            if lhs.isPrimaryCalendar != rhs.isPrimaryCalendar {
                return lhs.isPrimaryCalendar
            }
            let lhsDur = lhs.end.timeIntervalSince(lhs.start)
            let rhsDur = rhs.end.timeIntervalSince(rhs.start)
            if lhsDur != rhsDur { return lhsDur < rhsDur }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    /// "+N" suffix when the picked event has simultaneous siblings.
    private static func makeConflictSuffix(target: CalendarEvent, events: [CalendarEvent], now: Date) -> String {
        let active = events.filter { $0.myResponseStatus != "declined" }
        let count: Int
        if target.isInProgress {
            count = active.filter { $0.isInProgress && $0.id != target.id }.count
        } else {
            count = active.filter { $0.id != target.id && $0.start == target.start && $0.start > now }.count
        }
        return count > 0 ? " +\(count)" : ""
    }

    static func truncate(_ s: String) -> String {
        s.count > titleMaxChars ? String(s.prefix(titleMaxChars - 1)) + "…" : s
    }

    /// "1h 52m", "19m", "0m" — uses ceiling so 3m 45s reads as "4m" (matches Notion's behaviour
    /// and avoids "you have N minutes" undercounting actual time remaining).
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = max(0, Int(ceil(seconds / 60)))
        let h = mins / 60
        let m = mins % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
