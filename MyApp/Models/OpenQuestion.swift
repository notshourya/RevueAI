import Foundation
import SwiftData

/// An unresolved question raised during a review, with attribution and a
/// resolved flag.
@Model
final class OpenQuestion {
    var id: UUID = UUID()

    var text: String = ""

    /// Session-scoped speaker label of who raised the question.
    var attribution: String = ""

    var isResolved: Bool = false

    /// Capture order, used for stable sorting.
    var order: Int = 0

    /// Inverse of `ReviewNote.openQuestions`. Optional for CloudKit.
    var note: ReviewNote?

    init(
        id: UUID = UUID(),
        text: String = "",
        attribution: String = "",
        isResolved: Bool = false,
        order: Int = 0
    ) {
        self.id = id
        self.text = text
        self.attribution = attribution
        self.isResolved = isResolved
        self.order = order
    }
}
