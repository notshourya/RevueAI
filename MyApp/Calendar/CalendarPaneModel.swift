import Foundation
import Observation
import SwiftData

/// One meeting in the selected day's agenda, joined to its captured note
/// (by series id + occurrence date) and its series' capture history.
struct AgendaEntry: Identifiable {
    let event: MeetingEvent
    let note: ReviewNote?
    let seriesNoteCount: Int

    var id: String { event.id }
}

/// Month/agenda state for the calendar pane. Events are read live from the
/// provider; captured history joins against `MeetingSnapshot` records.
@MainActor
@Observable
final class CalendarPaneModel {
    var displayedMonth: Date = .now
    var selectedDay: Date = .now

    private let calendar: any MeetingCalendarProviding
    private let cal = Calendar.current

    init(calendar: any MeetingCalendarProviding) {
        self.calendar = calendar
    }

    var calendarProvider: any MeetingCalendarProviding { calendar }

    var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    func stepMonth(by delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }

    /// 42 cells (6 weeks × 7 days); nil for blanks outside the month.
    func monthDays() -> [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstWeekday = cal.component(.weekday, from: interval.start)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let dayCount = cal.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in 0..<dayCount {
            cells.append(cal.date(byAdding: .day, value: day, to: interval.start))
        }
        while cells.count < 42 { cells.append(nil) }
        return Array(cells.prefix(42))
    }

    /// Day-of-month numbers in the displayed month that have captured notes.
    func daysWithNotes(in context: ModelContext) -> Set<Int> {
        guard let interval = cal.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<MeetingSnapshot>(
            predicate: #Predicate { $0.occurrenceDate >= start && $0.occurrenceDate < end }
        )
        let snapshots = (try? context.fetch(descriptor)) ?? []
        return Set(snapshots.map { cal.component(.day, from: $0.occurrenceDate) })
    }

    /// The selected day's meetings, joined to captured notes and series history.
    func agenda(in context: ModelContext) -> [AgendaEntry] {
        guard let interval = cal.dateInterval(of: .day, for: selectedDay) else { return [] }
        return entries(in: interval, context: context)
    }

    /// The displayed month's meetings grouped by day-of-month — the full
    /// calendar surface's data source. One events fetch for the whole month.
    func monthAgenda(in context: ModelContext) -> [Int: [AgendaEntry]] {
        guard let interval = cal.dateInterval(of: .month, for: displayedMonth) else { return [:] }
        return Dictionary(grouping: entries(in: interval, context: context)) {
            cal.component(.day, from: $0.event.start)
        }
    }

    private func entries(in interval: DateInterval, context: ModelContext) -> [AgendaEntry] {
        let events = calendar.events(from: interval.start, to: interval.end)
        let snapshots = (try? context.fetch(FetchDescriptor<MeetingSnapshot>())) ?? []
        return events.map { event in
            let match = snapshots.first {
                $0.seriesID == event.seriesID && cal.isDate($0.occurrenceDate, inSameDayAs: event.start)
            }
            let seriesCount = snapshots.filter { $0.seriesID == event.seriesID && $0.note != nil }.count
            return AgendaEntry(event: event, note: match?.note, seriesNoteCount: seriesCount)
        }
    }
}
