import EventKit
import Foundation

/// An event from the Mac's Calendar, reduced to what a meeting note uses.
public struct CalendarEvent: Equatable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// False when the organizer cancelled the event or the user declined it.
    public var isAttending: Bool
    /// Invitees other than the user, by name, or by email when the invite gives no name.
    public var attendees: [String]
    public var videoURL: URL?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, isAttending: Bool = true, attendees: [String] = [],
                videoURL: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isAttending = isAttending
        self.attendees = attendees
        self.videoURL = videoURL
    }

    static let earlyStart: TimeInterval = 5 * 60
    private static let videoHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]

    /// The timed event the user attends at `now`, counting from five minutes before it starts; a video call wins, then the latest start.
    public static func current(_ events: [CalendarEvent], at now: Date) -> CalendarEvent? {
        events
            .filter { $0.isAttending && !$0.isAllDay && $0.start.addingTimeInterval(-earlyStart) <= now && now < $0.end }
            .max { ($0.videoURL == nil ? 0 : 1, $0.start) < ($1.videoURL == nil ? 0 : 1, $1.start) }
    }

    /// How a meeting lists an invitee: the name on the invite, else the email address, else nothing.
    static func invitee(name: String?, url: URL) -> String? {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        guard url.scheme?.lowercased() == "mailto", let email = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path,
              !email.isEmpty else { return nil }
        return email
    }

    /// The first Zoom, Google Meet, Microsoft Teams or Webex link in an event's URL, location or notes.
    public static func videoURL(in texts: [String]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return texts.lazy
            .flatMap { text in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url) }
            .first { url in
                guard let host = url.host()?.lowercased() else { return false }
                return videoHosts.contains { host == $0 || host.hasSuffix("." + $0) }
            }
    }
}

/// A Calendar account, such as iCloud, Google or Exchange, and the event calendars it shows on this Mac.
public struct CalendarAccount: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var calendars: [CalendarInfo]
}

public struct CalendarInfo: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
}

/// Reads events the Mac's Calendar already synced, so it works offline and never contacts calendar servers itself.
@MainActor
public final class CalendarEvents {
    private lazy var store = EKEventStore()

    public init() {}

    public static var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Shows the macOS Calendar permission prompt the first time; later calls return the saved answer.
    public func requestAccess() async -> Bool {
        let store = store
        let granted = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in continuation.resume(returning: granted) }
        }
        if granted { store.reset() }
        return granted
    }

    public func accounts() -> [CalendarAccount] {
        guard Self.isAuthorized else { return [] }
        let calendars = store.calendars(for: .event)
        return Dictionary(grouping: calendars) { $0.source?.sourceIdentifier ?? "" }
            .map { id, calendars in
                CalendarAccount(id: id, title: calendars[0].source?.title ?? "",
                                calendars: calendars.map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }
                                    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func current(excluding excluded: Set<String>, at now: Date = .now) -> CalendarEvent? {
        guard Self.isAuthorized else { return nil }
        let calendars = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return nil }
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(CalendarEvent.earlyStart), calendars: calendars)
        return CalendarEvent.current(store.events(matching: predicate).map(CalendarEvent.init), at: now)
    }
}

extension CalendarEvent {
    init(_ event: EKEvent) {
        self.init(
            id: event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            isAttending: event.status != .canceled && event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined,
            attendees: (event.attendees ?? [])
                .filter { !$0.isCurrentUser && $0.participantType != .room && $0.participantType != .resource }
                .compactMap { Self.invitee(name: $0.name, url: $0.url) },
            videoURL: Self.videoURL(in: [event.url?.absoluteString, event.location, event.notes].compactMap { $0 })
        )
    }
}
