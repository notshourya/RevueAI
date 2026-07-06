import Foundation
import FoundationModels

// MARK: - Live extraction schema

/// The typed result of a live extraction pass over a fresh transcript chunk.
/// Guided generation guarantees the model returns exactly this shape.
@Generable
struct ExtractedPoints {
    @Guide(description: "New action items surfaced in this chunk that are NOT already in the known points.")
    var actionItems: [ActionItemCandidate]

    @Guide(description: "Decisions made in this chunk.")
    var decisions: [DecisionCandidate]

    @Guide(description: "Open, unresolved questions raised in this chunk.")
    var openQuestions: [OpenQuestionCandidate]
}

@Generable
struct ActionItemCandidate: Equatable {
    @Guide(description: "A concise, actionable one-line summary of the task.")
    var oneLiner: String

    @Guide(description: "Who raised it: 'presenter' for the person presenting, or a reviewer label.")
    var attribution: String

    @Guide(description: "A short verbatim supporting quote from the discussion, if any.")
    var supportingQuote: String
}

@Generable
struct DecisionCandidate: Equatable {
    @Guide(description: "A concise statement of the decision that was made.")
    var statement: String

    @Guide(description: "Who made or drove the decision.")
    var attribution: String
}

@Generable
struct OpenQuestionCandidate: Equatable {
    @Guide(description: "The unresolved question, phrased clearly.")
    var question: String

    @Guide(description: "Who raised the question.")
    var attribution: String
}

// MARK: - Final polish schema

/// The typed result of the final polish pass over the whole transcript.
@Generable
struct PolishedReview {
    @Guide(description: "A 2-4 sentence summary of what was presented and the key decisions.")
    var summary: String

    @Guide(description: "The overall verdict for the review.")
    var verdict: GenerableVerdict

    @Guide(description: "The consolidated, de-duplicated action items with in-depth detail.")
    var actionItems: [PolishedActionItem]

    @Guide(description: "The unresolved open questions.")
    var openQuestions: [OpenQuestionCandidate]
}

/// Constrained verdict the model must choose from; mapped to `ReviewVerdict`.
@Generable
enum GenerableVerdict {
    case approved
    case needsChanges
    case rejected

    var reviewVerdict: ReviewVerdict {
        switch self {
        case .approved: return .approved
        case .needsChanges: return .needsChanges
        case .rejected: return .rejected
        }
    }
}

@Generable
struct PolishedActionItem {
    @Guide(description: "The concise, actionable one-liner.")
    var oneLiner: String

    @Guide(description: "In-depth detail: full context and the reasoning behind this item.")
    var inDepthDetail: String

    @Guide(description: "Who raised it.")
    var attribution: String

    @Guide(description: "Short verbatim supporting quotes from the discussion.")
    var supportingQuotes: [String]
}
