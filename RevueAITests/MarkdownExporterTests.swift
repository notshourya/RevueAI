import Foundation
import Testing
@testable import RevueAI

struct MarkdownExporterTests {
    @Test func rendersHeaderItemsAndQuestions() throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "API Review", summary: "Looked at the API.", verdict: .needsChanges)
        context.insert(note)
        let item = ActionItem(
            oneLiner: "Add retry logic",
            rationale: "Uploads fail on flaky networks.",
            inDepthDetail: "Wrap the upload call in exponential backoff.",
            attribution: "Reviewer 1",
            supportingQuotes: ["this will fail on bad wifi"],
            order: 0
        )
        item.note = note
        context.insert(item)
        let question = OpenQuestion(text: "Do we need pagination?", attribution: "Reviewer 1", order: 0)
        question.note = note
        context.insert(question)
        let decision = Decision(statement: "Ship behind a feature flag", attribution: "Reviewer 1", order: 0)
        decision.note = note
        context.insert(decision)

        let markdown = MarkdownExporter.markdown(for: note)
        #expect(markdown.contains("# API Review"))
        #expect(markdown.contains("## Summary"))
        #expect(markdown.contains("## Action Items"))
        #expect(markdown.contains("**Add retry logic**"))
        #expect(markdown.contains("> this will fail on bad wifi"))
        #expect(markdown.contains("## Open Questions"))
        #expect(markdown.contains("Do we need pagination?"))
        #expect(markdown.contains("## Decisions"))
        #expect(markdown.contains("- Ship behind a feature flag"))
    }
}
