import Foundation
import SwiftData

enum PolishError: Error {
    case allWindowsFailed
}

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

    func polish(note: ReviewNote, segments: [AudioSegment], context: ModelContext) async {
        note.status = .processing
        try? context.save()

        let livePoints = LiveExtractor.knownPointsSummary(for: note)
        do {
            let result: PolishedReview
            if TranscriptWindower.estimatedTokens(segments) <= model.contextTokenBudget {
                result = try await model.polish(
                    transcript: Self.transcriptText(for: segments),
                    livePoints: livePoints
                )
            } else {
                result = try await windowedPolish(segments: segments, livePoints: livePoints)
            }
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

    static func transcriptText(for segments: [AudioSegment]) -> String {
        segments
            .map { "[\($0.speakerHint.rawValue)] \($0.text)" }
            .joined(separator: "\n")
    }

    /// Map-reduce fallback for transcripts exceeding the backend's budget:
    /// extract enriched candidates per window (seeded with the live points so
    /// windows don't re-report known items), then consolidate the compact
    /// candidate list in one polish call.
    private func windowedPolish(segments: [AudioSegment], livePoints: String) async throws -> PolishedReview {
        let windows = TranscriptWindower.windows(for: segments, tokenBudget: model.contextTokenBudget)
        var known = livePoints
        var failures = 0
        for window in windows {
            do {
                let points = try await model.extractPoints(
                    fromChunk: Self.transcriptText(for: window),
                    knownPoints: known
                )
                known = Self.appendingCandidates(points, to: known)
            } catch {
                failures += 1
            }
        }
        guard failures < windows.count else { throw PolishError.allWindowsFailed }
        let digest = """
        POINTS PRE-EXTRACTED FROM THE FULL MEETING (the raw transcript was too \
        long to include; consolidate these):
        \(known.isEmpty ? "(none)" : known)
        """
        return try await model.polish(transcript: digest, livePoints: "")
    }

    private static func appendingCandidates(_ points: ExtractedPoints, to known: String) -> String {
        var lines = known.isEmpty ? [] : [known]
        for item in points.actionItems {
            var line = "- \(item.oneLiner) (raised by \(item.attribution))"
            if !item.supportingQuote.isEmpty { line += " — quote: \"\(item.supportingQuote)\"" }
            lines.append(line)
        }
        for decision in points.decisions {
            lines.append("• Decision: \(decision.statement) (\(decision.attribution))")
        }
        for question in points.openQuestions {
            lines.append("? \(question.question) (asked by \(question.attribution))")
        }
        return lines.joined(separator: "\n")
    }

    /// Replaces live-extracted items with the consolidated final set.
    private func apply(_ result: PolishedReview, to note: ReviewNote, context: ModelContext) {
        note.summary = result.summary
        note.verdict = result.verdict.reviewVerdict

        // User-touched items are locked: they survive polish verbatim and
        // near-duplicate AI versions of them are dropped below.
        let preserved = (note.actionItems ?? [])
            .filter { $0.userModified || $0.isUserCreated }
            .sorted { $0.order < $1.order }
        for existing in note.actionItems ?? [] where !existing.userModified && !existing.isUserCreated {
            context.delete(existing)
        }
        for (index, item) in preserved.enumerated() { item.order = index }
        for existing in note.openQuestions ?? [] { context.delete(existing) }
        for existing in note.decisions ?? [] { context.delete(existing) }
        for existing in note.speakers ?? [] { context.delete(existing) }

        // Code-level dedup safety net: skip near-identical one-liners the model
        // may still emit despite the merge instructions.
        var seen: [String] = preserved.map(\.oneLiner)
        var order = preserved.count
        for item in result.actionItems {
            guard !PointDedup.containsSimilar(item.oneLiner, in: seen) else { continue }
            seen.append(item.oneLiner)
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
            guard !PointDedup.containsSimilar(question.question, in: seenQuestions) else { continue }
            seenQuestions.append(question.question)
            let openQuestion = OpenQuestion(
                text: question.question,
                attribution: question.attribution,
                order: questionOrder
            )
            openQuestion.note = note
            context.insert(openQuestion)
            questionOrder += 1
        }

        var seenDecisions: [String] = []
        var decisionOrder = 0
        for decision in result.decisions {
            guard !PointDedup.containsSimilar(decision.statement, in: seenDecisions) else { continue }
            seenDecisions.append(decision.statement)
            let record = Decision(
                statement: decision.statement,
                attribution: decision.attribution,
                order: decisionOrder
            )
            record.note = note
            context.insert(record)
            decisionOrder += 1
        }

        var seenLabels: [String] = []
        for candidate in result.speakers {
            let label = candidate.label.trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, !seenLabels.contains(label) else { continue }
            seenLabels.append(label)
            let speaker = Speaker(label: label, isPresenter: candidate.isPresenter)
            speaker.note = note
            context.insert(speaker)
        }
    }
}
