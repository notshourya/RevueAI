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

        for (index, item) in result.actionItems.enumerated() {
            let actionItem = ActionItem(
                oneLiner: item.oneLiner,
                inDepthDetail: item.inDepthDetail,
                attribution: item.attribution,
                supportingQuotes: item.supportingQuotes,
                order: index
            )
            actionItem.note = note
            context.insert(actionItem)
        }

        for (index, question) in result.openQuestions.enumerated() {
            let openQuestion = OpenQuestion(
                text: question.question,
                attribution: question.attribution,
                order: index
            )
            openQuestion.note = note
            context.insert(openQuestion)
        }
    }
}
