import Foundation
import Testing
@testable import RevueAI

@MainActor
struct ReviewAssistantTests {
    @Test func appendsExchangesInOrder() async throws {
        let container = try makeInMemoryContainer()
        let fake = FakeAssistant()
        fake.results = [.success("Two items are open."), .success("Both are blockers.")]
        let assistant = ReviewAssistant(container: container, answering: fake)
        await assistant.ask("What's open?")
        await assistant.ask("How bad?")
        #expect(assistant.exchanges.map(\.answer) == ["Two items are open.", "Both are blockers."])
        #expect(assistant.exchanges.map(\.question) == ["What's open?", "How bad?"])
        #expect(!assistant.isThinking)
    }

    @Test func snapshotsSourcesPerExchange() async throws {
        let container = try makeInMemoryContainer()
        let note = ReviewNote(title: "Cited note")
        container.mainContext.insert(note)
        let fake = FakeAssistant()
        fake.results = [.success("answer")]
        let assistant = ReviewAssistant(container: container, answering: fake)
        fake.onAsk = { _ in assistant.sourceLogForTesting.record(note) }
        await assistant.ask("cite something")
        #expect(assistant.exchanges.first?.sources.map(\.title) == ["Cited note"])
    }

    @Test func failureMarksExchangeAndThreadSurvives() async throws {
        let container = try makeInMemoryContainer()
        let fake = FakeAssistant()
        fake.results = [.failure(FakeAssistantError()), .success("recovered")]
        let assistant = ReviewAssistant(container: container, answering: fake)
        await assistant.ask("first")
        await assistant.ask("second")
        #expect(assistant.exchanges.count == 2)
        #expect(assistant.exchanges[0].failed)
        #expect(assistant.exchanges[1].answer == "recovered")
    }

    @Test func ignoresEmptyQuestions() async throws {
        let container = try makeInMemoryContainer()
        let assistant = ReviewAssistant(container: container, answering: FakeAssistant())
        await assistant.ask("   ")
        #expect(assistant.exchanges.isEmpty)
    }

    @Test func clearDropsThreadAndConversation() async throws {
        let container = try makeInMemoryContainer()
        let fake = FakeAssistant()
        fake.results = [.success("a")]
        let assistant = ReviewAssistant(container: container, answering: fake)
        await assistant.ask("q")
        assistant.clear()
        #expect(assistant.exchanges.isEmpty)
    }
}
