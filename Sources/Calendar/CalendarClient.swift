import Foundation

enum CalendarClientError: Error {
    case http(Int, String)
    case decoding
    case syncTokenInvalid
}

struct EventListPage {
    let events: [CalendarEvent]
    let nextPageToken: String?
    let nextSyncToken: String?
    let deletedIDs: [String]
}

@MainActor
final class CalendarClient {
    private let auth = GoogleAuth.shared
    private let session = URLSession.shared
    /// Cached background colours keyed by `CalendarRef` so two accounts can share an ID without collision.
    private var calendarColors: [CalendarRef: String] = [:]

    func listCalendars(account: GoogleAccount) async throws -> [GoogleCalendarSummary] {
        let tokens = try await auth.refreshIfNeeded(account: account)
        var url = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        url.queryItems = [.init(name: "minAccessRole", value: "reader")]
        var req = URLRequest(url: url.url!)
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        try ensureOK(response, data: data)
        struct ListResp: Decodable { let items: [GoogleCalendarSummary] }
        let resp = try JSONDecoder().decode(ListResp.self, from: data)
        var stamped = resp.items
        for i in stamped.indices {
            stamped[i].accountID = account.id
            if let bg = stamped[i].backgroundColor {
                calendarColors[stamped[i].ref] = bg
            }
        }
        return stamped
    }

    func listEvents(
        account: GoogleAccount,
        calendarID: String,
        timeMin: Date,
        timeMax: Date,
        syncToken: String?,
        pageToken: String?
    ) async throws -> EventListPage {
        let tokens = try await auth.refreshIfNeeded(account: account)

        let escapedID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        var url = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(escapedID)/events")!
        var items: [URLQueryItem] = [
            .init(name: "singleEvents", value: "true"),
            .init(name: "showDeleted", value: "true"),
            .init(name: "maxResults", value: "250")
        ]
        if let syncToken {
            items.append(.init(name: "syncToken", value: syncToken))
        } else {
            items.append(.init(name: "timeMin", value: ISO8601DateFormatter().string(from: timeMin)))
            items.append(.init(name: "timeMax", value: ISO8601DateFormatter().string(from: timeMax)))
            items.append(.init(name: "orderBy", value: "startTime"))
        }
        if let pageToken { items.append(.init(name: "pageToken", value: pageToken)) }
        url.queryItems = items

        var req = URLRequest(url: url.url!)
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode == 410 {
            throw CalendarClientError.syncTokenInvalid
        }
        try ensureOK(response, data: data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let resp = try decoder.decode(GoogleEventsListResponse.self, from: data)

        let ref = CalendarRef(accountID: account.id, calendarID: calendarID)
        let calColor = calendarColors[ref]
        var events: [CalendarEvent] = []
        var deleted: [String] = []
        for item in resp.items {
            if item.status == "cancelled" {
                deleted.append(item.id)
                continue
            }
            guard let parsed = item.toEvent(
                accountID: account.id,
                calendarID: calendarID,
                calendarColorHex: calColor
            ) else { continue }
            events.append(parsed)
        }

        return EventListPage(
            events: events,
            nextPageToken: resp.nextPageToken,
            nextSyncToken: resp.nextSyncToken,
            deletedIDs: deleted
        )
    }

    private func ensureOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CalendarClientError.http(http.statusCode, body)
        }
    }
}

private struct GoogleEventsListResponse: Decodable {
    let items: [GoogleEventItem]
    let nextPageToken: String?
    let nextSyncToken: String?
}

private struct GoogleEventItem: Decodable {
    struct DateOrDateTime: Decodable {
        let date: String?
        let dateTime: String?
        let timeZone: String?
    }
    struct ConferenceData: Decodable {
        struct EntryPoint: Decodable {
            let entryPointType: String
            let uri: String?
        }
        let entryPoints: [EntryPoint]?
    }
    struct Attendee: Decodable {
        let isSelf: Bool?
        let responseStatus: String?
        enum CodingKeys: String, CodingKey {
            case isSelf = "self"
            case responseStatus
        }
    }

    let id: String
    let status: String
    let summary: String?
    let description: String?
    let location: String?
    let start: DateOrDateTime?
    let end: DateOrDateTime?
    let hangoutLink: String?
    let conferenceData: ConferenceData?
    let htmlLink: String?
    let attendees: [Attendee]?

    func toEvent(accountID: String, calendarID: String, calendarColorHex: String?) -> CalendarEvent? {
        guard let start, let end else { return nil }
        let isAllDay = start.date != nil && start.dateTime == nil
        let startDate: Date?
        let endDate: Date?
        if isAllDay {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = .current
            startDate = start.date.flatMap(f.date(from:))
            endDate = end.date.flatMap(f.date(from:))
        } else {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            startDate = start.dateTime.flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            endDate = end.dateTime.flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        }
        guard let s = startDate, let e = endDate else { return nil }

        let myResponse: String = attendees?.first(where: { $0.isSelf == true })?.responseStatus ?? "accepted"

        let conferenceURI = conferenceData?.entryPoints?
            .first(where: { $0.entryPointType == "video" })?.uri

        return CalendarEvent(
            id: id,
            accountID: accountID,
            calendarId: calendarID,
            title: summary ?? "(No title)",
            start: s,
            end: e,
            isAllDay: isAllDay,
            status: status,
            myResponseStatus: myResponse,
            location: location,
            description: description,
            hangoutLink: hangoutLink,
            conferenceUri: conferenceURI,
            htmlLink: htmlLink,
            calendarColorHex: calendarColorHex
        )
    }
}
