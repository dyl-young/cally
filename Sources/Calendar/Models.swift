import Foundation
import AppKit

/// Composite identity for a calendar — globally unique because two different Google accounts may
/// reference the same shared calendar by the same `calendarId`.
struct CalendarRef: Hashable, Codable {
    let accountID: String
    let calendarID: String
}

struct CalendarEvent: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let accountID: String
    let calendarId: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let status: String
    let myResponseStatus: String
    let location: String?
    let description: String?
    let hangoutLink: String?
    let conferenceUri: String?
    let htmlLink: String?
    let calendarColorHex: String?

    var calendarRef: CalendarRef { CalendarRef(accountID: accountID, calendarID: calendarId) }

    var meetLink: URL? {
        if let s = hangoutLink, let u = URL(string: s) { return u }
        if let s = conferenceUri, let u = URL(string: s),
           u.host?.contains("meet.google.com") == true { return u }
        return nil
    }

    var isInProgress: Bool {
        let now = Date()
        return now >= start && now < end
    }

    var hasStartedToday: Bool {
        Calendar.current.isDateInToday(start)
    }

    var calendarColor: NSColor {
        guard let hex = calendarColorHex else { return .systemBlue }
        return NSColor(hex: hex) ?? .systemBlue
    }
}

struct GoogleCalendarSummary: Codable, Identifiable, Hashable {
    let id: String
    let summary: String
    let primary: Bool?
    let backgroundColor: String?
    let selected: Bool?
    let accessRole: String?
    /// Filled in by `CalendarClient` after fetch — not part of Google's API response.
    var accountID: String = ""

    var ref: CalendarRef { CalendarRef(accountID: accountID, calendarID: id) }

    enum CodingKeys: String, CodingKey {
        case id, summary, primary, backgroundColor, selected, accessRole
    }
}
