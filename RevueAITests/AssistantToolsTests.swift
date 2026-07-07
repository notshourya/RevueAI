import Foundation
import Testing
import SwiftData
@testable import RevueAI

@MainActor
struct AssistantToolsTests {
    /// Fixture corpus: two notes across dates with items/questions/decisions.
    private func makeCorpus() throws -> (ModelContainer, SourceLog) {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let recent = ReviewNote(title: "Upload path review", date: .now.addingTimeInterval(-2 * 86_400))
        recent.summary = "Reviewed retry handling in the upload path."
        context.insert(recent)
        let retry = ActionItem(oneLiner: "Add retry logic to the upload path", tags: ["backend"], order: 0)
        retry.note = recent
        context.insert(retry)
        let doneItem = ActionItem(oneLiner: "Rename the flag", isDone: true, order: 1)
        doneItem.note = recent
        context.insert(doneItem)
        let question = OpenQuestion(text: "Do we need pagination?", order: 0)
        question.note = recent
        context.insert(question)
        let resolved = OpenQuestion(text: "Which bucket do uploads land in?", order: 1)
        resolved.isResolved = true
        resolved.note = recent
        context.insert(resolved)
        let decision = Decision(statement: "Ship behind a feature flag", order: 0)
        decision.note = recent
        context.insert(decision)

        let old = ReviewNote(title: "Auth review", date: .now.addingTimeInterval(-40 * 86_400))
        old.summary = "Token refresh discussion."
        context.insert(old)
        let oldItem = ActionItem(oneLiner: "Rotate signing keys", order: 0)
        oldItem.note = old
        context.insert(oldItem)

        try context.save()
        return (container, SourceLog())
    }

    @Test func searchFiltersByStatusAndLogsSources() async throws {
        let (container, log) = try makeCorpus()
        let tool = SearchActionItemsTool(container: container, sourceLog: log)
        let output = try await tool.call(arguments: .init(status: "open", tag: nil, matching: nil, sinceDays: nil))
        #expect(output.contains("Add retry logic"))
        #expect(output.contains("Rotate signing keys"))
        #expect(!output.contains("Rename the flag"))
        #expect(log.snapshot().map(\.title).sorted() == ["Auth review", "Upload path review"])
    }

    @Test func searchFiltersByTagAndRecency() async throws {
        let (container, log) = try makeCorpus()
        let tool = SearchActionItemsTool(container: container, sourceLog: log)
        let tagged = try await tool.call(arguments: .init(status: "any", tag: "backend", matching: nil, sinceDays: nil))
        #expect(tagged.contains("Add retry logic"))
        #expect(!tagged.contains("Rotate signing keys"))
        let recent = try await tool.call(arguments: .init(status: "any", tag: nil, matching: nil, sinceDays: 7))
        #expect(!recent.contains("Rotate signing keys"))
    }

    @Test func searchReportsNoMatches() async throws {
        let (container, log) = try makeCorpus()
        let tool = SearchActionItemsTool(container: container, sourceLog: log)
        let output = try await tool.call(arguments: .init(status: "open", tag: nil, matching: "kubernetes", sinceDays: nil))
        #expect(output.contains("No matching"))
        #expect(log.snapshot().isEmpty)
    }

    @Test func openQuestionsRespectsUnresolvedFlag() async throws {
        let (container, log) = try makeCorpus()
        let tool = ListOpenQuestionsTool(container: container, sourceLog: log)
        let unresolved = try await tool.call(arguments: .init(unresolvedOnly: true))
        #expect(unresolved.contains("pagination"))
        #expect(!unresolved.contains("bucket"))
        let all = try await tool.call(arguments: .init(unresolvedOnly: false))
        #expect(all.contains("bucket"))
    }

    @Test func summariesFilterByTextAndLogSources() async throws {
        let (container, log) = try makeCorpus()
        let tool = FetchNoteSummariesTool(container: container, sourceLog: log)
        let output = try await tool.call(arguments: .init(matching: "upload", sinceDays: nil))
        #expect(output.contains("Upload path review"))
        #expect(!output.contains("Auth review"))
        #expect(log.snapshot().map(\.title) == ["Upload path review"])
    }

    @Test func decisionsListAndLog() async throws {
        let (container, log) = try makeCorpus()
        let tool = ListDecisionsTool(container: container, sourceLog: log)
        let output = try await tool.call(arguments: .init(matching: nil, sinceDays: nil))
        #expect(output.contains("feature flag"))
        #expect(log.snapshot().map(\.title) == ["Upload path review"])
    }
}
