import Foundation
import AppKit

struct CalendarEvent: Identifiable, Codable, Equatable, Hashable {
    let id: String
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

struct GoogleCalendarSummary: Codable {
    let id: String
    let summary: String
    let primary: Bool?
    let backgroundColor: String?
    let selected: Bool?
    let accessRole: String?
}
