import Foundation

/// A calendar meeting as the app sees it — a plain value decoupled from
/// EventKit so everything downstream is testable and `EKEvent` never leaks.
struct MeetingEvent: Identifiable, Equatable, Sendable {
    /// EventKit's per-occurrence event identifier.
    let id: String
    /// Stable across occurrences of a recurring series.
    let seriesID: String
    let title: String
    let start: Date
    let end: Date
    let attendees: [String]
    let isRecurring: Bool
}

enum CalendarAuthorization {
    case notDetermined
    case authorized
    case denied
}

/// Read-only meeting source. The production implementation wraps EventKit;
/// tests use a fake.
protocol MeetingCalendarProviding {
    var authorization: CalendarAuthorization { get }
    func requestAccess() async -> Bool
    func events(from: Date, to: Date) -> [MeetingEvent]
}
