import Foundation
import SwiftData

/// Runs the live extraction pass over a fresh transcript chunk and checkpoints
/// new points to SwiftData immediately, so anything already extracted survives
/// a crash mid-meeting (the in-memory transcript itself is expendable by design).
@MainActor
final class LiveExtractor {
    private let model: any ReviewLanguageModel

    init(model: any ReviewLanguageModel) {
        self.model = model
    }

    /// Extracts from `chunk`, appends any new action items and open questions to
    /// `note`, saves, and returns the raw points (for the live panel).
    @discardableResult
    func extractAndCheckpoint(
        chunk: String,
        into note: ReviewNote,
        context: ModelContext
    ) async throws -> ExtractedPoints {
        let known = Self.knownPointsSummary(for: note)
        let points = try await model.extractPoints(fromChunk: chunk, knownPoints: known)

        var order = note.actionItems?.count ?? 0
        for candidate in points.actionItems {
            let quotes = candidate.supportingQuote.isEmpty ? [] : [candidate.supportingQuote]
            let item = ActionItem(
                oneLiner: candidate.oneLiner,
                attribution: candidate.attribution,
                supportingQuotes: quotes,
                order: order
            )
            item.note = note
            context.insert(item)
            order += 1
        }

        var questionOrder = note.openQuestions?.count ?? 0
        for candidate in points.openQuestions {
            let question = OpenQuestion(
                text: candidate.question,
                attribution: candidate.attribution,
                order: questionOrder
            )
            question.note = note
            context.insert(question)
            questionOrder += 1
        }

        try? context.save()
        return points
    }

    /// A compact list of the points already extracted, sent to the model so it
    /// only returns genuinely new items.
    static func knownPointsSummary(for note: ReviewNote) -> String {
        let items = note.sortedActionItems.map { "- \($0.oneLiner)" }
        let questions = note.sortedOpenQuestions.map { "? \($0.text)" }
        return (items + questions).joined(separator: "\n")
    }
}
