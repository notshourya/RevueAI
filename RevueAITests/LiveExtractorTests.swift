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

    @Test func knownPointsAreCappedForTheLivePass() throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        for i in 0..<30 {
            let item = ActionItem(oneLiner: "Item \(i)", order: i)
            item.note = note
            context.insert(item)
        }
        let capped = LiveExtractor.knownPointsSummary(for: note, limit: 25)
        let lines = capped.split(separator: "\n")
        #expect(lines.count == 26)
        #expect(lines.first == "(+5 earlier points)")
        #expect(lines.last == "- Item 29")

        let uncapped = LiveExtractor.knownPointsSummary(for: note)
        #expect(uncapped.split(separator: "\n").count == 30)
    }

    @Test func livePassSendsCappedKnownPoints() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        for i in 0..<30 {
            let item = ActionItem(oneLiner: "Item \(i)", order: i)
            item.note = note
            context.insert(item)
        }
        let model = FakeReviewModel()
        let extractor = LiveExtractor(model: model)
        try await extractor.extractAndCheckpoint(chunk: "[presenter] talk", into: note, context: context)
        let known = try #require(model.extractCalls.first?.knownPoints)
        #expect(known.contains("(+5 earlier points)"))
        #expect(!known.contains("- Item 0\n"))
    }

    @Test func persistsDecisions() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let model = FakeReviewModel()
        model.extractResults = [.success(ExtractedPoints(
            actionItems: [],
            decisions: [DecisionCandidate(statement: "Use SwiftData over Core Data", attribution: "presenter")],
            openQuestions: []
        ))]
        let extractor = LiveExtractor(model: model)
        try await extractor.extractAndCheckpoint(chunk: "[presenter] let's use SwiftData", into: note, context: context)
        #expect(note.sortedDecisions.map(\.statement) == ["Use SwiftData over Core Data"])
        #expect(note.sortedDecisions.first?.attribution == "presenter")
    }
}
