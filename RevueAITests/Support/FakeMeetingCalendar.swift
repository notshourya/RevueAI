import Foundation
@testable import RevueAI

final class FakeMeetingCalendar: MeetingCalendarProviding {
    var authorization: CalendarAuthorization = .authorized
    var stubbedEvents: [MeetingEvent] = []

    func requestAccess() async -> Bool { authorization == .authorized }

    func events(from: Date, to: Date) -> [MeetingEvent] {
        stubbedEvents.filter { $0.start >= from && $0.start <= to }
    }
}

extension MeetingEvent {
    static func stub(
        id: String = "evt-1",
        seriesID: String = "series-1",
        title: String = "Design review",
        start: Date = .now.addingTimeInterval(3600),
        attendees: [String] = ["Priya", "Marcus"],
        isRecurring: Bool = false
    ) -> MeetingEvent {
        MeetingEvent(id: id, seriesID: seriesID, title: title,
                     start: start, end: start.addingTimeInterval(1800),
                     attendees: attendees, isRecurring: isRecurring)
    }
}
