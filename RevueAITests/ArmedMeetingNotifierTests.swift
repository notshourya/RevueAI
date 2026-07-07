import Foundation
import Testing
import UserNotifications
@testable import RevueAI

@MainActor
struct ArmedMeetingNotifierTests {
    @Test func requestCarriesTitleTriggerAndCategory() {
        let planned = PlannedCapture(eventID: "e1", seriesID: "s1",
                                     occurrenceDate: Date(timeIntervalSince1970: 2_000_000_000),
                                     title: "Design review")
        let request = ArmedMeetingNotifier.request(for: planned)
        #expect(request.content.body.contains("Design review"))
        #expect(request.content.categoryIdentifier == "ARMED_MEETING")
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        #expect(trigger != nil)
        #expect(request.identifier == "armed-e1-2000000000")
    }

    @Test func requestIdentifierIsStablePerOccurrence() {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let a = ArmedMeetingNotifier.request(for: PlannedCapture(eventID: "e1", occurrenceDate: date, title: "A"))
        let b = ArmedMeetingNotifier.request(for: PlannedCapture(eventID: "e1", occurrenceDate: date, title: "B"))
        #expect(a.identifier == b.identifier)
    }
}
