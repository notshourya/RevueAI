import Foundation
import SwiftData

/// A finished (or in-progress) review note — the only artifact that persists.
///
/// The schema is deliberately CloudKit-compatible from day one: no unique
/// constraints, every relationship optional, and defaults on every stored
/// property. This lets us switch on SwiftData + CloudKit mirroring later
/// without a migration.
@Model
final class ReviewNote {
    /// Stable identifier used for deep-linking and export. Not a unique
    /// constraint (CloudKit disallows those); just a value we generate.
    var id: UUID = UUID()

    var title: String = ""
    var date: Date = Date.now
    /// Wall-clock length of the captured session, in seconds.
    var durationSeconds: Double = 0

    /// Summary of what was presented and the key decisions.
    var summary: String = ""

    // Stored as the enum's raw value indirectly via SwiftData's Codable
    // support. Defaults keep CloudKit happy.
    var verdict: ReviewVerdict = ReviewVerdict.pending
    var status: ProcessingStatus = ProcessingStatus.capturing

    /// Whether this review has been archived (hidden from the main library).
    var isArchived: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ActionItem.note)
    var actionItems: [ActionItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \OpenQuestion.note)
    var openQuestions: [OpenQuestion]? = []

    @Relationship(deleteRule: .cascade, inverse: \Speaker.note)
    var speakers: [Speaker]? = []

    init(
        id: UUID = UUID(),
        title: String = "",
        date: Date = .now,
        durationSeconds: Double = 0,
        summary: String = "",
        verdict: ReviewVerdict = .pending,
        status: ProcessingStatus = .capturing
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.durationSeconds = durationSeconds
        self.summary = summary
        self.verdict = verdict
        self.status = status
    }

    /// Action items sorted by priority (most urgent first), then capture order.
    var sortedActionItems: [ActionItem] {
        (actionItems ?? []).sorted {
            $0.priority.sortRank != $1.priority.sortRank
                ? $0.priority.sortRank < $1.priority.sortRank
                : $0.order < $1.order
        }
    }

    /// Open questions sorted by their capture order.
    var sortedOpenQuestions: [OpenQuestion] {
        (openQuestions ?? []).sorted { $0.order < $1.order }
    }
}
