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

    /// Layer 1 — the concise, actionable one-liner shown in lists.
    var oneLiner: String = ""

    /// Layer 2 — one sentence on why this matters (revealed on first expand).
    var rationale: String = ""

    /// Layer 3 — expanded detail: full reasoning and context.
    var inDepthDetail: String = ""

    /// Session-scoped speaker label of who raised it (e.g. "Reviewer 1").
    var attribution: String = ""

    /// Layer 4 — short verbatim quotes from the discussion supporting this item.
    var supportingQuotes: [String] = []

    // Priority/category are stored as OPTIONAL raw strings so that adding them
    // to a store that already has rows migrates cleanly (SwiftData doesn't
    // backfill enum defaults, which crashes a non-optional enum on read).
    // Non-optional enums are exposed via the computed accessors below.
    private var priorityRaw: String?
    private var categoryRaw: String?

    var priority: ActionPriority {
        get { priorityRaw.flatMap(ActionPriority.init(rawValue:)) ?? .major }
        set { priorityRaw = newValue.rawValue }
    }
    var category: ActionCategory {
        get { categoryRaw.flatMap(ActionCategory.init(rawValue:)) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var isDone: Bool = false

    /// Capture order, used for stable sorting (CloudKit to-many is unordered).
    var order: Int = 0

    /// Inverse of `ReviewNote.actionItems`. Optional for CloudKit.
    var note: ReviewNote?

    init(
        id: UUID = UUID(),
        oneLiner: String = "",
        rationale: String = "",
        inDepthDetail: String = "",
        attribution: String = "",
        supportingQuotes: [String] = [],
        priority: ActionPriority = .major,
        category: ActionCategory = .other,
        isDone: Bool = false,
        order: Int = 0
    ) {
        self.id = id
        self.oneLiner = oneLiner
        self.rationale = rationale
        self.inDepthDetail = inDepthDetail
        self.attribution = attribution
        self.supportingQuotes = supportingQuotes
        self.priorityRaw = priority.rawValue
        self.categoryRaw = category.rawValue
        self.isDone = isDone
        self.order = order
    }

    /// Whether there are deeper layers to reveal beyond the one-liner.
    var hasDepth: Bool {
        !rationale.isEmpty || !inDepthDetail.isEmpty || !supportingQuotes.isEmpty
    }
}
