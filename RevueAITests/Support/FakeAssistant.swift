import Foundation
import FoundationModels
@testable import RevueAI

/// Scripted assistant backend: pops canned results per question. The
/// `onAsk` hook lets tests simulate tool activity (e.g. recording sources).
final class FakeAssistant: AssistantAnswering, @unchecked Sendable {
    var isAvailable = true
    var results: [Result<String, Error>] = []
    var onAsk: (@MainActor (String) -> Void)?

    func makeConversation(tools: [any Tool]) -> any AssistantConversing {
        FakeConversation(owner: self)
    }

    final class FakeConversation: AssistantConversing, @unchecked Sendable {
        let owner: FakeAssistant
        init(owner: FakeAssistant) { self.owner = owner }

        func ask(_ question: String) async throws -> String {
            await owner.onAsk?(question)
            guard !owner.results.isEmpty else { return "canned answer" }
            return try owner.results.removeFirst().get()
        }
    }
}

struct FakeAssistantError: Error {}
