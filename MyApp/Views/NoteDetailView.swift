import SwiftUI
import SwiftData
import AppKit

/// A dense, compact reading view: a slim header, a tight summary strip, and a
/// parallel board (To Do · Completed · Questions).
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VerdictBadge(verdict: note.verdict)
                Text(note.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if note.durationSeconds > 0 {
                    Text("· \(durationText)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            TextField("Title", text: $note.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
        }
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
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summaryStrip: some View {
        if !note.summary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Summary", systemImage: "text.alignleft")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(note.summary)
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(.primary.opacity(0.9))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassEffect(.regular.tint(Theme.panel.opacity(0.22)), in: .rect(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.panelStroke, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var decisionsStrip: some View {
        let decisions = note.sortedDecisions
        if !decisions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Decisions", systemImage: "checkmark.seal")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                ForEach(decisions) { decision in
                    DecisionRow(decision: decision)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassEffect(.regular.tint(Theme.panel.opacity(0.22)), in: .rect(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.panelStroke, lineWidth: 1)
            )
        }
    }
}

/// One decision line; click shows its detail in an anchored popover.
private struct DecisionRow: View {
    let decision: Decision
    @State private var showDetail = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(decision.statement)
        }
        .font(Theme.rounded(13))
        .foregroundStyle(.primary.opacity(0.9))
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail, arrowEdge: .trailing) {
            DecisionDetail(decision: decision)
        }
    }
}
