import Foundation
import SwiftData

/// A session-scoped speaker label ("You", "Reviewer 1", or a real name heard
/// in the meeting). Persisted so attributions in a note remain meaningful.
@Model
final class Speaker {
    var id: UUID = UUID()

    /// The display label for this speaker within its review session.
    var label: String = ""

    /// Whether this speaker is the presenter/local user (mic stream origin).
    var isPresenter: Bool = false

    /// Inverse of `ReviewNote.speakers`. Optional for CloudKit.
    var note: ReviewNote?

    init(
        id: UUID = UUID(),
        label: String = "",
        isPresenter: Bool = false
    ) {
        self.id = id
        self.label = label
        self.isPresenter = isPresenter
    }
}
