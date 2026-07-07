import Foundation
import FoundationModels
import Observation
import SwiftData

enum AssistantPrompts {
    static let instructions = """
    You answer questions about the user's review notes. You MUST use the \
    provided tools to look up anything you state — action items, questions, \
    decisions, or summaries. Answer concisely from tool results only. When a \
    search returns nothing, say so plainly. Never fabricate notes, items, \
    dates, or quotes.
    """
}

/// One ongoing question-answer session (kept so follow-ups carry context).
protocol AssistantConversing {
    func ask(_ question: String) async throws -> String
}

/// The model backend seam — production wraps a LanguageModelSession; tests fake it.
protocol AssistantAnswering: Sendable {
    var isAvailable: Bool { get }
    @MainActor func makeConversation(tools: [any Tool]) -> any AssistantConversing
}

/// Production backend on the on-device model.
struct OnDeviceAssistant: AssistantAnswering {
    var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: true
        default: false
        }
    }

    func makeConversation(tools: [any Tool]) -> any AssistantConversing {
        SessionConversation(session: LanguageModelSession(tools: tools,
                                                          instructions: AssistantPrompts.instructions))
    }

    private final class SessionConversation: AssistantConversing {
        let session: LanguageModelSession
        init(session: LanguageModelSession) { self.session = session }

        func ask(_ question: String) async throws -> String {
            try await session.respond(to: question).content
        }
    }
}

/// The assistant panel's model: a session-only thread of exchanges, each
/// carrying deterministic sources from the tool log.
@MainActor
@Observable
final class ReviewAssistant {
    struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        var answer: String
        var sources: [SourceRef]
        var failed: Bool
    }

    private(set) var exchanges: [Exchange] = []
    private(set) var isThinking = false

    var isAvailable: Bool { answering.isAvailable }

    private let container: ModelContainer
    private let answering: any AssistantAnswering
    private let sourceLog = SourceLog()
    private var conversation: (any AssistantConversing)?

    /// Test hook: lets fakes simulate tool activity against the real log.
    var sourceLogForTesting: SourceLog { sourceLog }

    init(container: ModelContainer, answering: any AssistantAnswering = OnDeviceAssistant()) {
        self.container = container
        self.answering = answering
    }

    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        isThinking = true
        defer { isThinking = false }

        sourceLog.reset()
        if conversation == nil {
            conversation = answering.makeConversation(tools: makeTools())
        }
        do {
            let answer = try await conversation!.ask(trimmed)
            exchanges.append(Exchange(question: trimmed, answer: answer,
                                      sources: sourceLog.snapshot(), failed: false))
        } catch {
            exchanges.append(Exchange(question: trimmed,
                                      answer: "Couldn't answer that — try rephrasing or ask again.",
                                      sources: [], failed: true))
        }
    }

    func clear() {
        exchanges = []
        conversation = nil
        sourceLog.reset()
    }

    private func makeTools() -> [any Tool] {
        [
            SearchActionItemsTool(container: container, sourceLog: sourceLog),
            ListOpenQuestionsTool(container: container, sourceLog: sourceLog),
            FetchNoteSummariesTool(container: container, sourceLog: sourceLog),
            ListDecisionsTool(container: container, sourceLog: sourceLog),
        ]
    }
}
