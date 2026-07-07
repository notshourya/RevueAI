import Foundation
import Testing
@testable import RevueAI

@MainActor
struct CalendarPaneModelTests {
    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, hour: Int = 10) -> Date {
        DateComponents(calendar: .current, year: year, month: month, day: dayOfMonth, hour: hour).date!
    }

    @Test func monthGridHasFortyTwoCells() {
        let model = CalendarPaneModel(calendar: FakeMeetingCalendar())
        model.displayedMonth = day(2026, 7, 1)
        let cells = model.monthDays()
        #expect(cells.count == 42)
        #expect(cells.compactMap { $0 }.count == 31)
    }

    @Test func agendaJoinsEventsToCapturedNotes() throws {
        let context = try makeInMemoryContext()
        let start = day(2026, 7, 15)
        let fake = FakeMeetingCalendar()
        fake.stubbedEvents = [
            MeetingEvent.stub(id: "e1", seriesID: "s1", title: "Sprint review", start: start),
            MeetingEvent.stub(id: "e2", seriesID: "s2", title: "1:1", start: start.addingTimeInterval(3600)),
        ]
        let note = ReviewNote(title: "Sprint review")
        context.insert(note)
        let snapshot = MeetingSnapshot(title: "Sprint review", seriesID: "s1", occurrenceDate: start)
        snapshot.note = note
        context.insert(snapshot)
        try context.save()

        let model = CalendarPaneModel(calendar: fake)
        model.displayedMonth = start
        model.selectedDay = start
        let agenda = model.agenda(in: context)
        #expect(agenda.count == 2)
        #expect(agenda[0].note?.title == "Sprint review")
        #expect(agenda[0].seriesNoteCount == 1)
        #expect(agenda[1].note == nil)
    }

    @Test func daysWithNotesMarksSnapshotDays() throws {
        let context = try makeInMemoryContext()
        let snapshot = MeetingSnapshot(title: "R", seriesID: "s", occurrenceDate: day(2026, 7, 9))
        context.insert(snapshot)
        try context.save()
        let model = CalendarPaneModel(calendar: FakeMeetingCalendar())
        model.displayedMonth = day(2026, 7, 1)
        #expect(model.daysWithNotes(in: context).contains(9))
        #expect(!model.daysWithNotes(in: context).contains(10))
    }
}
