import Foundation
import EventKit

/// EventKit-backed meeting source. Reads are always live — Apple Calendar
/// owns syncing (Google/Exchange/iCloud/.ics). Republishes store-change
/// notifications so views can refresh.
@MainActor
final class CalendarService: MeetingCalendarProviding {
    private let store = EKEventStore()

    var authorization: CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func events(from: Date, to: Date) -> [MeetingEvent] {
        guard authorization == .authorized else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).map { event in
            MeetingEvent(
                id: event.eventIdentifier ?? UUID().uuidString,
                seriesID: event.calendarItemIdentifier,
                title: event.title ?? "Untitled",
                start: event.startDate,
                end: event.endDate,
                attendees: (event.attendees ?? []).compactMap(\.name),
                isRecurring: event.hasRecurrenceRules
            )
        }
        .sorted { $0.start < $1.start }
    }

    /// Fires whenever the underlying store changes (Apple Calendar synced).
    var changePublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
    }
}
