import Foundation
import SwiftData

/// Runs the final polish pass on stop: sends the whole transcript + live points
/// to the backend, then replaces the note's live-extracted content with the
/// consolidated, de-duplicated result (summary, verdict, in-depth action items,
/// open questions).
@MainActor
final class FinalPolisher {
    private let model: any ReviewLanguageModel

    init(model: any ReviewLanguageModel) {
        self.model = model
    }

    func polish(note: ReviewNote, transcript: String, context: ModelContext) async {
        note.status = .processing
        try? context.save()

        let livePoints = LiveExtractor.knownPointsSummary(for: note)
        do {
            let result = try await model.polish(transcript: transcript, livePoints: livePoints)
            apply(result, to: note, context: context)
            // On-device is the default backend for now; mark accordingly so the
            // note can be re-polished by PCC later when that path is enabled.
            note.status = (model is PrivateCloudReviewModel) ? .polished : .processedOnDevice
        } catch {
            // Preserve whatever live points were already checkpointed.
            note.status = .processedOnDevice
        }
        try? context.save()
    }

    /// Replaces live-extracted items with the consolidated final set.
    private func apply(_ result: PolishedReview, to note: ReviewNote, context: ModelContext) {
        note.summary = result.summary
        note.verdict = result.verdict.reviewVerdict

        for existing in note.actionItems ?? [] { context.delete(existing) }
        for existing in note.openQuestions ?? [] { context.delete(existing) }

        // Code-level dedup safety net: skip near-identical one-liners the model
        // may still emit despite the merge instructions.
        var seen: [String] = []
        var order = 0
        for item in result.actionItems {
            let key = Self.normalize(item.oneLiner)
            guard !key.isEmpty, !seen.contains(where: { Self.similar($0, key) }) else { continue }
            seen.append(key)
            let actionItem = ActionItem(
                oneLiner: item.oneLiner,
                rationale: item.rationale,
                inDepthDetail: item.inDepthDetail,
                attribution: item.attribution,
                supportingQuotes: item.supportingQuotes,
                priority: item.priority.priority,
                category: item.category.category,
                order: order
            )
            actionItem.note = note
            context.insert(actionItem)
            order += 1
        }

        var seenQuestions: [String] = []
        var questionOrder = 0
        for question in result.openQuestions {
            let key = Self.normalize(question.question)
            guard !key.isEmpty, !seenQuestions.contains(where: { Self.similar($0, key) }) else { continue }
            seenQuestions.append(key)
            let openQuestion = OpenQuestion(
                text: question.question,
                attribution: question.attribution,
                order: questionOrder
            )
            openQuestion.note = note
            context.insert(openQuestion)
            questionOrder += 1
        }
    }

    /// Normalizes a phrase to lowercase alphanumeric words for comparison.
    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// True when two normalized phrases are near-duplicates — one contains the
    /// other, or they share at least 80% of the smaller phrase's words.
    private static func similar(_ a: String, _ b: String) -> Bool {
        if a == b || a.contains(b) || b.contains(a) { return true }
        let wordsA = Set(a.split(separator: " "))
        let wordsB = Set(b.split(separator: " "))
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return false }
        let overlap = wordsA.intersection(wordsB).count
        return Double(overlap) / Double(min(wordsA.count, wordsB.count)) >= 0.8
    }
}
