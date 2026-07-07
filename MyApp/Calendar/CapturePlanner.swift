import Foundation
import SwiftData

/// Arm/disarm bookkeeping for planned captures. Matching is by event id +
/// occurrence date so each occurrence of a recurring meeting arms separately.
@MainActor
enum CapturePlanner {
    /// How long after start time an armed meeting still counts as "due".
    static let dueWindow: TimeInterval = 15 * 60
    /// Planned captures older than this get pruned.
    static let staleAfter: TimeInterval = 2 * 60 * 60

    static func plannedCapture(for event: MeetingEvent, in context: ModelContext) -> PlannedCapture? {
        let id = event.id
        let date = event.start
        var descriptor = FetchDescriptor<PlannedCapture>(
            predicate: #Predicate { $0.eventID == id && $0.occurrenceDate == date }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func isArmed(_ event: MeetingEvent, in context: ModelContext) -> Bool {
        plannedCapture(for: event, in: context) != nil
    }

    static func arm(_ event: MeetingEvent, in context: ModelContext) {
        guard !isArmed(event, in: context) else { return }
        let planned = PlannedCapture(eventID: event.id, seriesID: event.seriesID,
                                     occurrenceDate: event.start, title: event.title)
        context.insert(planned)
        try? context.save()
    }

    static func disarm(_ event: MeetingEvent, in context: ModelContext) {
        guard let planned = plannedCapture(for: event, in: context) else { return }
        context.delete(planned)
        try? context.save()
    }

    /// Removes and returns the planned capture for a starting meeting.
    @discardableResult
    static func consume(eventID: String, occurrenceDate: Date, in context: ModelContext) -> PlannedCapture? {
        var descriptor = FetchDescriptor<PlannedCapture>(
            predicate: #Predicate { $0.eventID == eventID && $0.occurrenceDate == occurrenceDate }
        )
        descriptor.fetchLimit = 1
        guard let planned = try? context.fetch(descriptor).first else { return nil }
        let copy = PlannedCapture(eventID: planned.eventID, seriesID: planned.seriesID,
                                  occurrenceDate: planned.occurrenceDate, title: planned.title)
        context.delete(planned)
        try? context.save()
        return copy
    }

    /// Drops planned captures whose occurrence is long past (event deleted,
    /// meeting missed — either way the prompt window is over).
    static func prune(now: Date, in context: ModelContext) {
        let cutoff = now.addingTimeInterval(-staleAfter)
        let all = (try? context.fetch(FetchDescriptor<PlannedCapture>())) ?? []
        for planned in all where planned.occurrenceDate < cutoff {
            context.delete(planned)
        }
        try? context.save()
    }

    /// The armed meeting that has just started (within the due window), if any.
    static func duePrompt(now: Date, in context: ModelContext) -> PlannedCapture? {
        let all = (try? context.fetch(FetchDescriptor<PlannedCapture>())) ?? []
        return all
            .filter { $0.occurrenceDate <= now && now.timeIntervalSince($0.occurrenceDate) <= dueWindow }
            .sorted { $0.occurrenceDate > $1.occurrenceDate }
            .first
    }
}
