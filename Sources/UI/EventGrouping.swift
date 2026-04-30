import Foundation

struct EventSection {
    let id: String
    let title: String
    let events: [CalendarEvent]
}

enum EventGrouping {
    /// Groups events into sections matching Notion: "Ending in Xm" (current event),
    /// "Today", "Tomorrow", and a named day for day-3 (e.g. "Fri 1 May").
    static func group(events: [CalendarEvent], now: Date = Date()) -> [EventSection] {
        var sections: [EventSection] = []
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let dayAfter = cal.date(byAdding: .day, value: 2, to: today)!
        let endOfDay3 = cal.date(byAdding: .day, value: 3, to: today)!

        // In-progress event(s)
        let inProgress = events.filter { $0.isInProgress }
        if let current = inProgress.first {
            let remaining = current.end.timeIntervalSince(now)
            let label = "Ending in \(TitleFormatter.formatDuration(remaining))"
            sections.append(EventSection(id: "now", title: label, events: inProgress))
        }

        // Today (excluding in-progress)
        let todayEvents = events.filter {
            !$0.isInProgress &&
            $0.start >= now &&
            $0.start < tomorrow
        }
        if !todayEvents.isEmpty {
            sections.append(EventSection(id: "today", title: "Today", events: todayEvents))
        }

        // Tomorrow
        let tomorrowEvents = events.filter {
            $0.start >= tomorrow && $0.start < dayAfter
        }
        if !tomorrowEvents.isEmpty {
            sections.append(EventSection(id: "tomorrow", title: "Tomorrow", events: tomorrowEvents))
        }

        // Day after (named)
        let day3Events = events.filter {
            $0.start >= dayAfter && $0.start < endOfDay3
        }
        if !day3Events.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "EEE d MMM"
            sections.append(EventSection(id: "day3", title: f.string(from: dayAfter), events: day3Events))
        }

        return sections
    }
}
