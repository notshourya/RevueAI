# Review Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tool-calling assistant over the note corpus: four typed SwiftData tools, deterministic source citations, a session-thread panel in the inspector, and a Siri App Intent.

**Architecture:** Foundation Models `LanguageModelSession(tools:)` on the on-device model. Tools are `Sendable` structs holding `(ModelContainer, SourceLog)`; because `Tool.call` is `@concurrent`, each tool hops to the main actor for its fetch and source logging. Citations come only from `SourceLog` (never the model). `ReviewAssistant` (`@MainActor @Observable`) owns the exchange thread behind an `AssistantAnswering` seam so tests fake the model while tools are tested directly against a fixture corpus.

**Tech Stack:** FoundationModels (Tool, @Generable, LanguageModelSession), SwiftData, SwiftUI inspector, App Intents, Swift Testing.

## Global Constraints

- **Toolchain:** prefix every `xcodebuild` with `DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer`.
- **Test command:** `DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' 2>&1 | grep -E "error:|✘|Test run|TEST (SUCCEEDED|FAILED)"` — success is `Test run with N tests ... passed` + `** TEST SUCCEEDED **`. Never `-quiet`.
- **Baseline:** 75 tests in 14 suites pass before Task 1.
- **Citations never come from the model** — source chips are built from `SourceLog` records only.
- **Native-neutral UI**: system colors/materials; no brand theming outside the blob.
- **Verified SDK API shapes (do not re-derive):** `LanguageModelSession(model: .default, tools: [any Tool], instructions: String?)`; `session.respond(to: String)` → `.content: String`; `protocol Tool` needs `name`, `description`, `@Generable Arguments` (gets `parameters` for free), and `@concurrent func call(arguments:) async throws -> String` (String is `PromptRepresentable`).
- Conversations are session-only; never persisted.

---

### Task 1: SourceLog + container test support

**Files:**
- Create: `MyApp/Assistant/SourceLog.swift`
- Modify: `RevueAITests/Support/TestSupport.swift:5-17` (expose the container)
- Create: `RevueAITests/SourceLogTests.swift`

**Interfaces:**
- Produces: `struct SourceRef: Identifiable, Equatable, Sendable { let id: UUID; let title: String }`; `@MainActor final class SourceLog { func record(_ note: ReviewNote); func snapshot() -> [SourceRef]; func reset() }` — dedup by note id, first-recorded order, capped at 8. `makeInMemoryContainer() throws -> ModelContainer` in TestSupport (and `makeInMemoryContext` now derives from it).

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/SourceLogTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

@MainActor
struct SourceLogTests {
    @Test func dedupsAndPreservesFirstRecordedOrder() throws {
        let context = try makeInMemoryContext()
        let first = ReviewNote(title: "First")
        let second = ReviewNote(title: "Second")
        context.insert(first)
        context.insert(second)
        let log = SourceLog()
        log.record(first)
        log.record(second)
        log.record(first)
        let refs = log.snapshot()
        #expect(refs.map(\.title) == ["First", "Second"])
    }

    @Test func capsAtEight() throws {
        let context = try makeInMemoryContext()
        let log = SourceLog()
        for index in 0..<12 {
            let note = ReviewNote(title: "Note \(index)")
            context.insert(note)
            log.record(note)
        }
        #expect(log.snapshot().count == 8)
        #expect(log.snapshot().first?.title == "Note 0")
    }

    @Test func resetEmptiesTheLog() throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "N")
        context.insert(note)
        let log = SourceLog()
        log.record(note)
        log.reset()
        #expect(log.snapshot().isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the Global Constraints test command.
Expected: build error — `cannot find 'SourceLog' in scope`.

- [ ] **Step 3: Implement SourceLog and the container helper**

Create `MyApp/Assistant/SourceLog.swift`:

```swift
import Foundation

/// A note the assistant's answer drew from. Built only from tool activity —
/// the model never emits identifiers.
struct SourceRef: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
}

/// Collects the notes touched by tool calls while answering one question.
/// Deduped by note id, first-recorded order, capped so the chip row stays sane.
@MainActor
final class SourceLog {
    private var refs: [SourceRef] = []
    private static let cap = 8

    func record(_ note: ReviewNote) {
        guard !refs.contains(where: { $0.id == note.id }), refs.count < Self.cap else { return }
        refs.append(SourceRef(id: note.id, title: note.title))
    }

    func snapshot() -> [SourceRef] { refs }

    func reset() { refs = [] }
}
```

In `RevueAITests/Support/TestSupport.swift`, replace the `makeInMemoryContext` function with:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Global Constraints test command.
Expected: `Test run with 78 tests in 15 suites passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyApp/Assistant RevueAITests
git commit -m "feat: SourceLog — deterministic citation collection for the assistant"
```

---

### Task 2: The four assistant tools

**Files:**
- Create: `MyApp/Assistant/AssistantTools.swift`
- Create: `RevueAITests/AssistantToolsTests.swift`

**Interfaces:**
- Consumes: `SourceLog` (Task 1), the SwiftData models.
- Produces: `SearchActionItemsTool`, `ListOpenQuestionsTool`, `FetchNoteSummariesTool`, `ListDecisionsTool` — each `init(container: ModelContainer, sourceLog: SourceLog)`, conforming to `Tool` with `@Generable` Arguments and `call -> String`. Shared helpers `assistantDateCutoff(sinceDays:)` and result formatting stay private. Every result line format is fixed in this task and relied on by tests only.

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/AssistantToolsTests.swift`:

```swift
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
```

Note: `ActionItem(oneLiner:tags:order:)` and `(oneLiner:isDone:order:)` — parameter order in the init is `isDone`, then `tags`, then `userModified`… before `order`; adjust call sites to the declared order if the compiler complains.

- [ ] **Step 2: Run tests to verify they fail**

Run the Global Constraints test command.
Expected: build error — `cannot find 'SearchActionItemsTool' in scope`.

- [ ] **Step 3: Implement the tools**

Create `MyApp/Assistant/AssistantTools.swift`:

```swift
import Foundation
import FoundationModels
import SwiftData

// The assistant's four lookup tools. Each is Sendable (Tool.call is
// @concurrent) and hops to the main actor for its SwiftData fetch, recording
// touched notes in the SourceLog so citations stay deterministic.

private let resultCap = 20
private let dateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)

private func cutoff(sinceDays: Int?) -> Date? {
    sinceDays.map { Date.now.addingTimeInterval(-Double($0) * 86_400) }
}

private func capped(_ lines: [String], noun: String) -> String {
    guard !lines.isEmpty else { return "No matching \(noun) found." }
    return lines.prefix(resultCap).joined(separator: "\n")
}

struct SearchActionItemsTool: Tool {
    let name = "searchActionItems"
    let description = """
    Search action items across all review notes. Filter by status ('open', \
    'done', or 'any'), an exact tag, a text fragment, or recency in days.
    """
    let container: ModelContainer
    let sourceLog: SourceLog

    @Generable
    struct Arguments {
        @Guide(description: "Completion filter: 'open', 'done', or 'any'.")
        var status: String?
        @Guide(description: "Only items carrying exactly this tag.")
        var tag: String?
        @Guide(description: "Case-insensitive fragment of the item text.")
        var matching: String?
        @Guide(description: "Only from notes captured within this many days.")
        var sinceDays: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let items = (try? container.mainContext.fetch(FetchDescriptor<ActionItem>())) ?? []
            let since = cutoff(sinceDays: arguments.sinceDays)
            let filtered = items
                .filter { item in
                    switch arguments.status?.lowercased() {
                    case "open": !item.isDone
                    case "done": item.isDone
                    default: true
                    }
                }
                .filter { item in arguments.tag.map { item.tags.contains($0) } ?? true }
                .filter { item in
                    arguments.matching.map { item.oneLiner.localizedCaseInsensitiveContains($0) } ?? true
                }
                .filter { item in since.map { (item.note?.date ?? .distantPast) >= $0 } ?? true }
                .sorted { ($0.note?.date ?? .distantPast) > ($1.note?.date ?? .distantPast) }
            let lines = filtered.prefix(resultCap).map { item -> String in
                if let note = item.note { sourceLog.record(note) }
                let status = item.isDone ? "done" : "open"
                let noteInfo = item.note.map { " (\($0.title), \($0.date.formatted(dateStyle)))" } ?? ""
                let tags = item.tags.isEmpty ? "" : " tags: \(item.tags.joined(separator: ","))"
                return "– \(item.oneLiner) [\(item.priority.displayName), \(status)]\(tags)\(noteInfo)"
            }
            return capped(Array(lines), noun: "action items")
        }
    }
}

struct ListOpenQuestionsTool: Tool {
    let name = "listOpenQuestions"
    let description = "List open questions from all reviews, optionally only unresolved ones."
    let container: ModelContainer
    let sourceLog: SourceLog

    @Generable
    struct Arguments {
        @Guide(description: "True to list only questions not yet resolved.")
        var unresolvedOnly: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let questions = (try? container.mainContext.fetch(FetchDescriptor<OpenQuestion>())) ?? []
            let filtered = questions
                .filter { arguments.unresolvedOnly ? !$0.isResolved : true }
                .sorted { ($0.note?.date ?? .distantPast) > ($1.note?.date ?? .distantPast) }
            let lines = filtered.prefix(resultCap).map { question -> String in
                if let note = question.note { sourceLog.record(note) }
                let status = question.isResolved ? "resolved" : "unresolved"
                let noteInfo = question.note.map { " (\($0.title))" } ?? ""
                return "? \(question.text) [\(status)]\(noteInfo)"
            }
            return capped(Array(lines), noun: "questions")
        }
    }
}

struct FetchNoteSummariesTool: Tool {
    let name = "fetchNoteSummaries"
    let description = "Fetch review note titles, dates, verdicts, and summaries. Filter by a text fragment or recency in days."
    let container: ModelContainer
    let sourceLog: SourceLog

    @Generable
    struct Arguments {
        @Guide(description: "Case-insensitive fragment of the note title or summary.")
        var matching: String?
        @Guide(description: "Only notes captured within this many days.")
        var sinceDays: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let notes = (try? container.mainContext.fetch(FetchDescriptor<ReviewNote>())) ?? []
            let since = cutoff(sinceDays: arguments.sinceDays)
            let filtered = notes
                .filter { note in
                    arguments.matching.map {
                        note.title.localizedCaseInsensitiveContains($0)
                            || note.summary.localizedCaseInsensitiveContains($0)
                    } ?? true
                }
                .filter { note in since.map { note.date >= $0 } ?? true }
                .sorted { $0.date > $1.date }
            let lines = filtered.prefix(resultCap).map { note -> String in
                sourceLog.record(note)
                return "\(note.title) (\(note.date.formatted(dateStyle)), \(note.verdict.displayName)): \(note.summary)"
            }
            return capped(Array(lines), noun: "notes")
        }
    }
}

struct ListDecisionsTool: Tool {
    let name = "listDecisions"
    let description = "List decisions recorded across reviews. Filter by a text fragment or recency in days."
    let container: ModelContainer
    let sourceLog: SourceLog

    @Generable
    struct Arguments {
        @Guide(description: "Case-insensitive fragment of the decision.")
        var matching: String?
        @Guide(description: "Only from notes captured within this many days.")
        var sinceDays: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let decisions = (try? container.mainContext.fetch(FetchDescriptor<Decision>())) ?? []
            let since = cutoff(sinceDays: arguments.sinceDays)
            let filtered = decisions
                .filter { decision in
                    arguments.matching.map { decision.statement.localizedCaseInsensitiveContains($0) } ?? true
                }
                .filter { decision in since.map { (decision.note?.date ?? .distantPast) >= $0 } ?? true }
                .sorted { ($0.note?.date ?? .distantPast) > ($1.note?.date ?? .distantPast) }
            let lines = filtered.prefix(resultCap).map { decision -> String in
                if let note = decision.note { sourceLog.record(note) }
                let noteInfo = decision.note.map { " (\($0.title))" } ?? ""
                return "• \(decision.statement)\(noteInfo)"
            }
            return capped(Array(lines), noun: "decisions")
        }
    }
}
```

If the compiler rejects `sourceLog` capture inside `MainActor.run` (Sendable complaint), the fix is that `SourceLog` is `@MainActor` and therefore implicitly Sendable — check the error before restructuring; a `nonisolated(unsafe)` workaround is NOT acceptable.

Check `ReviewNote` for a `verdict.displayName` — `ReviewVerdict` has `displayName` (used by `VerdictBadge`). If `OpenQuestion.isResolved` has a different spelling, match the model.

- [ ] **Step 4: Run tests to verify they pass**

Run the Global Constraints test command.
Expected: `Test run with 84 tests in 16 suites passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyApp/Assistant RevueAITests
git commit -m "feat: assistant tools — typed SwiftData lookups with source logging"
```

---

### Task 3: AssistantAnswering seam + ReviewAssistant

**Files:**
- Create: `MyApp/Assistant/ReviewAssistant.swift`
- Create: `RevueAITests/ReviewAssistantTests.swift`
- Create: `RevueAITests/Support/FakeAssistant.swift`

**Interfaces:**
- Consumes: the four tools + `SourceLog` (Tasks 1–2).
- Produces:
  - `protocol AssistantAnswering: Sendable { var isAvailable: Bool { get }; @MainActor func makeConversation(tools: [any Tool]) -> any AssistantConversing }`
  - `protocol AssistantConversing { func ask(_ question: String) async throws -> String }`
  - `OnDeviceAssistant` (production; wraps `LanguageModelSession`).
  - `@MainActor @Observable final class ReviewAssistant`: `struct Exchange: Identifiable { let id: UUID; let question: String; var answer: String; var sources: [SourceRef]; var failed: Bool }`; `private(set) var exchanges: [Exchange]`; `private(set) var isThinking: Bool`; `var isAvailable: Bool`; `init(container: ModelContainer, answering: any AssistantAnswering = OnDeviceAssistant())`; `func ask(_ question: String) async`; `func clear()`.
  - `AssistantPrompts.instructions: String`.

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/Support/FakeAssistant.swift`:

```swift
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
```

Create `RevueAITests/ReviewAssistantTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run the Global Constraints test command.
Expected: build error — `cannot find type 'AssistantAnswering' in scope`.

- [ ] **Step 3: Implement**

Create `MyApp/Assistant/ReviewAssistant.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Global Constraints test command.
Expected: `Test run with 89 tests in 17 suites passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyApp/Assistant RevueAITests
git commit -m "feat: ReviewAssistant — session thread over the tool-calling seam"
```

---

### Task 4: Assistant panel + toolbar button

**Files:**
- Create: `MyApp/Views/AssistantPanelView.swift`
- Modify: `MyApp/Views/Shell/RootShellView.swift` (sparkles toggle + inspector + assistant state)

**Interfaces:**
- Consumes: `ReviewAssistant`, `SourceRef`.
- Produces: `AssistantPanelView(assistant:onOpenNote:)`. RootShell owns `@State assistant: ReviewAssistant?` (created on appear from `context.container`) and `@State showAssistant = false`.

- [ ] **Step 1: Build the panel**

Create `MyApp/Views/AssistantPanelView.swift`:

```swift
import SwiftUI
import SwiftData

/// The Review Assistant panel: a query field over a session thread of
/// exchanges, each answer carrying deterministic source chips.
struct AssistantPanelView: View {
    var assistant: ReviewAssistant
    var onOpenNote: (UUID) -> Void

    @State private var question = ""

    var body: some View {
        VStack(spacing: 0) {
            if assistant.isAvailable {
                queryField
                Divider()
                thread
            } else {
                unavailable
            }
        }
        .navigationTitle("Assistant")
    }

    private var queryField: some View {
        HStack(spacing: 8) {
            TextField("Ask about your reviews…", text: $question)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                .disabled(assistant.isThinking)
            if !assistant.exchanges.isEmpty {
                Button {
                    assistant.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear the conversation")
            }
        }
        .padding(10)
    }

    private func submit() {
        let text = question
        question = ""
        Task { await assistant.ask(text) }
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if assistant.exchanges.isEmpty && !assistant.isThinking {
                        emptyHint
                    }
                    ForEach(assistant.exchanges) { exchange in
                        ExchangeView(exchange: exchange, onOpenNote: onOpenNote)
                            .id(exchange.id)
                    }
                    if assistant.isThinking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Looking through your notes…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .id("thinking")
                    }
                }
                .padding(12)
            }
            .onChange(of: assistant.exchanges.count) {
                withAnimation { proxy.scrollTo(assistant.exchanges.last?.id, anchor: .bottom) }
            }
            .onChange(of: assistant.isThinking) { _, thinking in
                if thinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask across all your reviews:")
                .font(.callout.weight(.medium))
            Text("“Which action items are still open?”\n“What did we decide about the upload path?”\n“Summarize last week's reviews.”")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("Apple Intelligence is off")
                .font(.headline)
            Text("Turn it on in System Settings to ask questions about your reviews.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ExchangeView: View {
    let exchange: ReviewAssistant.Exchange
    var onOpenNote: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exchange.question)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(exchange.answer)
                .font(.callout)
                .foregroundStyle(exchange.failed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .textSelection(.enabled)
            if !exchange.sources.isEmpty {
                FlowLayoutish {
                    ForEach(exchange.sources) { source in
                        Button {
                            onOpenNote(source.id)
                        } label: {
                            Label(source.title, systemImage: "doc.text")
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Open this note")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

(`FlowLayoutish` already exists in `MyApp/Views/ItemPopup.swift` at internal visibility.)

- [ ] **Step 2: Wire the inspector and toolbar**

In `MyApp/Views/Shell/RootShellView.swift`:

Add state:

```swift
    @State private var showAssistant = false
    @State private var assistant: ReviewAssistant?
```

Add after the `NavigationSplitView`'s closing brace (chain with the existing modifiers, before `.onChange(of: coordinator.state)`):

```swift
        .inspector(isPresented: $showAssistant) {
            if let assistant {
                AssistantPanelView(assistant: assistant) { noteID in
                    openNote(id: noteID)
                }
                .inspectorColumnWidth(min: 280, ideal: 330)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showAssistant.animation(.smooth)) {
                    Label("Assistant", systemImage: "sparkles")
                }
                .toggleStyle(.button)
                .help(showAssistant ? "Hide the assistant" : "Ask about your reviews")
            }
        }
```

Extend the existing `.onAppear` block (the one gating onboarding) with:

```swift
            if assistant == nil {
                assistant = ReviewAssistant(container: context.container)
            }
```

Add the note-jump helper alongside `startFromPlanned`:

```swift
    private func openNote(id: UUID) {
        var descriptor = FetchDescriptor<ReviewNote>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let note = try? context.fetch(descriptor).first else { return }
        withAnimation(.smooth) {
            showCalendarSurface = false
            selection = note
        }
    }
```

- [ ] **Step 3: Run the suite, build, verify by hand**

Run the Global Constraints test command.
Expected: `Test run with 89 tests in 17 suites passed`, `** TEST SUCCEEDED **`.

Build and launch:

```bash
DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer xcodebuild build -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' 2>&1 | grep -E "^\*\* BUILD"; pkill -x RevueAI; sleep 1; open ~/Library/Developer/Xcode/DerivedData/RevueAI-*/Build/Products/Debug/RevueAI.app
```

Click the sparkles button → panel opens; ask "which action items are open?" → answer appears with source chips; clicking a chip selects the note; a follow-up ("which of those are blockers?") works in context.

- [ ] **Step 4: Commit**

```bash
git add MyApp
git commit -m "feat: assistant panel in the inspector with source chips"
```

---

### Task 5: Siri App Intent

**Files:**
- Create: `MyApp/Assistant/AskRevueAIIntent.swift`
- Create: `MyApp/SharedModel.swift`
- Modify: `MyApp/RevueAIApp.swift:10-30` (use the shared container)

**Interfaces:**
- Consumes: `ReviewAssistant` (Task 3).
- Produces: `SharedModel.container: ModelContainer` (single source of truth for the store); `AskRevueAIIntent` + `RevueAIShortcuts`.

- [ ] **Step 1: Extract the shared container**

Create `MyApp/SharedModel.swift`:

```swift
import Foundation
import SwiftData

/// The app's single model container — shared by the UI scene and App
/// Intents so Siri answers from the same store.
enum SharedModel {
    static let container: ModelContainer = {
        let schema = Schema([
            ReviewNote.self,
            ActionItem.self,
            OpenQuestion.self,
            Decision.self,
            Speaker.self,
            PlannedCapture.self,
            MeetingSnapshot.self,
        ])
        // Local store for Milestone 1. The schema is CloudKit-ready, so
        // enabling iCloud sync later is a configuration change, not a migration.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
```

In `MyApp/RevueAIApp.swift`, delete the `init()` and the `private let container: ModelContainer` property, and replace every `container` reference in the scene with `SharedModel.container` (the `.modelContainer(SharedModel.container)` calls on both scenes).

- [ ] **Step 2: Write the intent**

Create `MyApp/Assistant/AskRevueAIIntent.swift`:

```swift
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
```

- [ ] **Step 3: Full suite + build + verify**

Run the Global Constraints test command.
Expected: `Test run with 89 tests in 17 suites passed`, `** TEST SUCCEEDED **`.

Build (same command as Task 4 Step 3). Manual check: Shortcuts app shows "Ask" under RevueAI; running it with a question returns a spoken/shown answer.

- [ ] **Step 4: Commit**

```bash
git add MyApp
git commit -m "feat: Ask RevueAI Siri intent over the shared container"
```

---

## Final verification (after Task 5)

- [ ] Full suite → `** TEST SUCCEEDED **`, 89 tests in 17 suites.
- [ ] Build → `** BUILD SUCCEEDED **`.
- [ ] Manual (needs the user): with a few captured notes, ask cross-note questions in the panel; verify source chips open the right notes, follow-ups keep context, Clear resets, and the Siri shortcut answers.
