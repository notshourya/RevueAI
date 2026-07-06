import Foundation
import SwiftData

/// A concrete, checkable action item extracted from a review.
///
/// Each item is a one-liner plus an in-depth subsection: full detail, who
/// raised it, and short supporting quotes — the only verbatim text that
/// persists from the discussion.
@Model
final class ActionItem {
    var id: UUID = UUID()

    /// The concise, actionable one-liner shown in lists.
    var oneLiner: String = ""

    /// Expanded detail: reasoning and context for the in-depth subsection.
    var inDepthDetail: String = ""

    /// Session-scoped speaker label of who raised it (e.g. "Reviewer 1").
    var attribution: String = ""

    /// Short verbatim quotes from the discussion supporting this item.
    var supportingQuotes: [String] = []

    var isDone: Bool = false

    /// Capture order, used for stable sorting (CloudKit to-many is unordered).
    var order: Int = 0

    /// Inverse of `ReviewNote.actionItems`. Optional for CloudKit.
    var note: ReviewNote?

    init(
        id: UUID = UUID(),
        oneLiner: String = "",
        inDepthDetail: String = "",
        attribution: String = "",
        supportingQuotes: [String] = [],
        isDone: Bool = false,
        order: Int = 0
    ) {
        self.id = id
        self.oneLiner = oneLiner
        self.inDepthDetail = inDepthDetail
        self.attribution = attribution
        self.supportingQuotes = supportingQuotes
        self.isDone = isDone
        self.order = order
    }
}
