import Foundation

/// A note the assistant's answer drew from. Built only from tool activity —
/// the model never emits identifiers.
struct SourceRef: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
}

/// Collects the notes touched by tool calls while answering one question.
/// Deduped by note id, first-recorded order, capped so the chip row stays sane.
@MainActor
final class SourceLog {
    private var refs: [SourceRef] = []
    private static let cap = 8

    func record(_ note: ReviewNote) {
        guard !refs.contains(where: { $0.id == note.id }), refs.count < Self.cap else { return }
        refs.append(SourceRef(id: note.id, title: note.title))
    }

    func snapshot() -> [SourceRef] { refs }

    func reset() { refs = [] }
}
