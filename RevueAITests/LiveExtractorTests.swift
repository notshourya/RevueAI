import Foundation
import Testing
@testable import RevueAI

struct LiveExtractorTests {
    @Test func checkpointsExtractedPointsToTheNote() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let model = FakeReviewModel()
        model.extractResults = [.success(ExtractedPoints(
            actionItems: [ActionItemCandidate(
                oneLiner: "Add index to users table",
                attribution: "Reviewer",
                supportingQuote: "this query is slow"
            )],
            decisions: [],
            openQuestions: [OpenQuestionCandidate(
                question: "Do we need pagination?",
                attribution: "Reviewer"
            )]
        ))]
        let extractor = LiveExtractor(model: model)
        try await extractor.extractAndCheckpoint(
            chunk: "[reviewer] this query is slow",
            into: note,
            context: context
        )
        #expect(note.sortedActionItems.map(\.oneLiner) == ["Add index to users table"])
        #expect(note.sortedActionItems.first?.supportingQuotes == ["this query is slow"])
        #expect(note.sortedOpenQuestions.map(\.text) == ["Do we need pagination?"])
    }

    @Test func sendsKnownPointsToTheModel() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let existing = ActionItem(oneLiner: "Fix crash on launch", order: 0)
        existing.note = note
        context.insert(existing)
        let model = FakeReviewModel()
        let extractor = LiveExtractor(model: model)
        try await extractor.extractAndCheckpoint(chunk: "[presenter] more talk", into: note, context: context)
        let known = try #require(model.extractCalls.first?.knownPoints)
        #expect(known.contains("- Fix crash on launch"))
    }
}
