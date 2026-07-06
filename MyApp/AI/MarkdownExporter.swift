import Foundation

/// Renders a `ReviewNote` as agent-ready Markdown — deliberately formatted as
/// context you can drop into a coding agent ("this was the review; make these
/// changes"). Delivers the review-to-code story from phase 1.
enum MarkdownExporter {
    static func markdown(for note: ReviewNote) -> String {
        var lines: [String] = []
        lines.append("# \(note.title)")
        lines.append("")
        lines.append("**Date:** \(note.date.formatted(date: .long, time: .shortened))  ")
        lines.append("**Verdict:** \(note.verdict.displayName)")
        lines.append("")

        if !note.summary.isEmpty {
            lines.append("## Summary")
            lines.append("")
            lines.append(note.summary)
            lines.append("")
        }

        let items = note.sortedActionItems
        if !items.isEmpty {
            lines.append("## Action Items")
            lines.append("")
            for item in items {
                var head = "- [\(item.isDone ? "x" : " ")] **\(item.oneLiner)**"
                if !item.attribution.isEmpty { head += " _(raised by \(item.attribution))_" }
                lines.append(head)
                if !item.inDepthDetail.isEmpty {
                    lines.append("  - \(item.inDepthDetail)")
                }
                for quote in item.supportingQuotes where !quote.isEmpty {
                    lines.append("  - > \(quote)")
                }
            }
            lines.append("")
        }

        let questions = note.sortedOpenQuestions
        if !questions.isEmpty {
            lines.append("## Open Questions")
            lines.append("")
            for question in questions {
                var line = "- [\(question.isResolved ? "x" : " ")] \(question.text)"
                if !question.attribution.isEmpty { line += " _(asked by \(question.attribution))_" }
                lines.append(line)
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Writes the Markdown to a temporary `.md` file (inside the app container,
    /// so no file entitlement is required) and returns its URL for sharing.
    static func temporaryFileURL(for note: ReviewNote) throws -> URL {
        let safeName = note.title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
        let name = safeName.isEmpty ? "Review" : safeName
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).md")
        try markdown(for: note).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
