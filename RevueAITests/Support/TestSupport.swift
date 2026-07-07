import Foundation
import SwiftData
@testable import RevueAI

/// A fresh in-memory SwiftData container mirroring the app's schema.
func makeInMemoryContainer() throws -> ModelContainer {
    let schema = Schema([
        ReviewNote.self,
        ActionItem.self,
        OpenQuestion.self,
        Decision.self,
        Speaker.self,
        PlannedCapture.self,
        MeetingSnapshot.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

/// A fresh in-memory SwiftData context mirroring the app's schema.
func makeInMemoryContext() throws -> ModelContext {
    ModelContext(try makeInMemoryContainer())
}

extension ExtractedPoints {
    static var empty: ExtractedPoints {
        ExtractedPoints(actionItems: [], decisions: [], openQuestions: [])
    }
}

extension PolishedReview {
    static func stub(
        summary: String = "A solid review.",
        verdict: GenerableVerdict = .needsChanges,
        actionItems: [PolishedActionItem] = [],
        openQuestions: [OpenQuestionCandidate] = [],
        decisions: [DecisionCandidate] = [],
        speakers: [SpeakerCandidate] = []
    ) -> PolishedReview {
        PolishedReview(
            summary: summary,
            verdict: verdict,
            actionItems: actionItems,
            openQuestions: openQuestions,
            decisions: decisions,
            speakers: speakers
        )
    }
}

extension PolishedActionItem {
    static func stub(
        _ oneLiner: String,
        attribution: String = "Reviewer",
        priority: GenerablePriority = .major,
        category: GenerableCategory = .bug,
        quotes: [String] = []
    ) -> PolishedActionItem {
        PolishedActionItem(
            oneLiner: oneLiner,
            rationale: "Because it matters.",
            inDepthDetail: "Detail.",
            attribution: attribution,
            supportingQuotes: quotes,
            priority: priority,
            category: category
        )
    }
}
