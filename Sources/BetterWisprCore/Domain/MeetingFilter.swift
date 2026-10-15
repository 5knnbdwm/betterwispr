import Foundation

/// Narrows the meetings Ask reads when asking across meetings.
public struct MeetingFilter: Equatable, Sendable {
    /// Days back from today, counting today as the first; nil for any date.
    public var days: Int?
    /// A Calendar invitee the meeting must list; nil for anyone.
    public var attendee: String?

    public init(days: Int? = nil, attendee: String? = nil) {
        self.days = days
        self.attendee = attendee
    }

    public func apply(to meetings: [Meeting], calendar: Calendar = .current, now: Date = .now) -> [Meeting] {
        let start = days.flatMap { calendar.date(byAdding: .day, value: 1 - $0, to: calendar.startOfDay(for: now)) }
        return meetings.filter { meeting in
            (start.map { meeting.createdAt >= $0 } ?? true) && (attendee.map { meeting.attendees?.contains($0) == true } ?? true)
        }
    }

    /// Every Calendar invitee across `meetings` once, in Finder's name order.
    public static func attendees(in meetings: [Meeting]) -> [String] {
        Set(meetings.flatMap { $0.attendees ?? [] }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
