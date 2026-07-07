import AppIntents
import Foundation

/// "Ask RevueAI…" — answers a question about the note corpus via the same
/// tool-calling assistant, headlessly. Opens no UI.
struct AskRevueAIIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask RevueAI"
    static let description = IntentDescription("Ask a question about your review notes.")

    @Parameter(title: "Question")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let assistant = ReviewAssistant(container: SharedModel.container)
        guard assistant.isAvailable else {
            return .result(dialog: "Apple Intelligence is off, so I can't answer questions about your reviews.")
        }
        await assistant.ask(question)
        guard let exchange = assistant.exchanges.last, !exchange.failed else {
            return .result(dialog: "I couldn't answer that — try rephrasing.")
        }
        var dialog = exchange.answer
        if !exchange.sources.isEmpty {
            let titles = exchange.sources.prefix(3).map(\.title).joined(separator: ", ")
            dialog += " From: \(titles)."
        }
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct RevueAIShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskRevueAIIntent(),
            phrases: ["Ask \(.applicationName)"],
            shortTitle: "Ask",
            systemImageName: "sparkles"
        )
    }
}
