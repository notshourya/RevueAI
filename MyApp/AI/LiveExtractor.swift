import Foundation
import SwiftData

/// Runs the live extraction pass over a fresh transcript chunk and checkpoints
/// new points to SwiftData immediately, so anything already extracted survives
/// a crash mid-meeting (the in-memory transcript itself is expendable by design).
@MainActor
final class LiveExtractor {
    /// Most recent points sent to the live pass — bounds context on long meetings.
    static let liveKnownPointsLimit = 25

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
        let known = Self.knownPointsSummary(for: note, limit: Self.liveKnownPointsLimit)
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

    /// A compact list of the points already extracted, in capture order. Pass
    /// `limit` to keep only the most recent entries (live pass); the final
    /// pass omits it and sees everything.
    static func knownPointsSummary(for note: ReviewNote, limit: Int? = nil) -> String {
        let items = (note.actionItems ?? [])
            .sorted { $0.order < $1.order }
            .map { "- \($0.oneLiner)" }
        let questions = (note.openQuestions ?? [])
            .sorted { $0.order < $1.order }
            .map { "? \($0.text)" }
        var entries = items + questions
        if let limit, entries.count > limit {
            let omitted = entries.count - limit
            entries = ["(+\(omitted) earlier points)"] + entries.suffix(limit)
        }
        return entries.joined(separator: "\n")
    }
}
