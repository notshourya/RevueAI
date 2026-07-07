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
