import SwiftUI
import SwiftData
import AppKit

/// The reading view: a hero header with stat chips, summary and decision
/// cards in the app's adaptive glass, and the parallel board below.
struct NoteDetailView: View {
    @Bindable var note: ReviewNote

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if note.status == .processing { processingRow }
                summaryStrip
                decisionsStrip
                ReviewBoard(note: note)
                Color.clear.frame(height: 24)
            }
            .padding(24)
            .frame(maxWidth: 1300, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background { PremiumBackground() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VerdictBadge(verdict: note.verdict)
                Text(note.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                if note.durationSeconds > 0 {
                    Text("· \(durationText)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            TextField("Title", text: $note.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 30, weight: .bold, design: .rounded))
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
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
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
            VStack(alignment: .leading, spacing: 8) {
                Label("SUMMARY", systemImage: "text.alignleft")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)
                Text(note.summary)
                    .font(.system(size: 14, design: .rounded))
                    .lineSpacing(4)
                    .foregroundStyle(.primary.opacity(0.92))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .contentCard()
        }
    }

    @ViewBuilder
    private var decisionsStrip: some View {
        let decisions = note.sortedDecisions
        if !decisions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("DECISIONS", systemImage: "checkmark.seal")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)
                ForEach(decisions) { decision in
                    DecisionRow(decision: decision)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .contentCard()
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
                .font(.system(size: 11))
                .foregroundStyle(Theme.success.opacity(0.85))
            Text(decision.statement)
                .font(.system(size: 13.5, design: .rounded))
        }
        .foregroundStyle(.primary.opacity(0.92))
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail, arrowEdge: .trailing) {
            DecisionDetail(decision: decision)
        }
    }
}
