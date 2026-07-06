import Foundation
import SwiftData

/// A decision made during a review, with attribution. Extracted live and
/// consolidated by the final pass, like action items and open questions.
@Model
final class Decision {
    var id: UUID = UUID()

    /// A concise statement of what was decided.
    var statement: String = ""

    /// Session-scoped speaker label of who made or drove the decision.
    var attribution: String = ""

    /// Capture order, used for stable sorting.
    var order: Int = 0

    /// Inverse of `ReviewNote.decisions`. Optional for CloudKit.
    var note: ReviewNote?

    init(
        id: UUID = UUID(),
        statement: String = "",
        attribution: String = "",
        order: Int = 0
    ) {
        self.id = id
        self.statement = statement
        self.attribution = attribution
        self.order = order
    }
}
