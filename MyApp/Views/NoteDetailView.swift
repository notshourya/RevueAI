import SwiftUI
import SwiftData
import AppKit

/// The reading view: a clean, open-page layout — no card boxes. Summary and
/// decisions read as editorial sections; the verdict badge carries the only
/// status color, and the board's item rows are the only glass surfaces.
struct NoteDetailView: View {
    @Bindable var note: ReviewNote
    /// Live page width so the layout re-flows when the window resizes or
    /// the sidebar collapses.
    @State private var pageWidth: CGFloat = 0

    private var isWide: Bool { pageWidth >= 1000 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                if note.status == .processing { processingRow }
                if isWide && !note.summary.isEmpty && !note.sortedDecisions.isEmpty {
                    // Wide: summary and decisions share the row instead of
                    // stacking into a long left-hugging column.
                    HStack(alignment: .top, spacing: 56) {
                        summaryStrip
                        decisionsStrip
                            .frame(maxWidth: max(340, pageWidth * 0.34), alignment: .leading)
                    }
                } else {
                    summaryStrip
                    decisionsStrip
                }
                ReviewBoard(note: note)
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background { PremiumBackground() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VerdictBadge(verdict: note.verdict)
                Text(note.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                if note.durationSeconds > 0 {
                    Text("· \(durationText)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            TextField("Title", text: $note.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
            statChips
        }
    }

    /// At-a-glance chips: open, done, questions.
    private var statChips: some View {
        let open = note.sortedActionItems.filter { !$0.isDone }.count
        let done = note.sortedActionItems.count - open
        let questions = note.sortedOpenQuestions.filter { !$0.isResolved }.count
        return HStack(spacing: 8) {
            statChip("\(open) open", systemImage: "circle.dashed", tint: .secondary)
            if done > 0 {
                statChip("\(done) done", systemImage: "checkmark.circle.fill", tint: Theme.success)
            }
            if questions > 0 {
                statChip("\(questions) question\(questions == 1 ? "" : "s")",
                         systemImage: "questionmark.circle", tint: Theme.warning)
            }
            Spacer()
        }
    }

    private func statChip(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
    }

    private var durationText: String {
        let minutes = Int(note.durationSeconds) / 60
        let seconds = Int(note.durationSeconds) % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    private var processingRow: some View {
        HStack(spacing: 10) {
            StateOrb(mode: .processing, size: 28)
            Text("Summarizing your review…")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summaryStrip: some View {
        if !note.summary.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("SUMMARY", systemImage: "text.alignleft")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)
                Text(note.summary)
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .lineSpacing(8)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 900, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var decisionsStrip: some View {
        let decisions = note.sortedDecisions
        if !decisions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("DECISIONS", systemImage: "checkmark.seal")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)
                ForEach(decisions) { decision in
                    DecisionRow(decision: decision)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One decision line; click shows its detail in an anchored popover.
private struct DecisionRow: View {
    let decision: Decision
    @State private var showDetail = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.success)
            Text(decision.statement)
                .font(.system(size: 16, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail, arrowEdge: .trailing) {
            DecisionDetail(decision: decision)
        }
    }
}
