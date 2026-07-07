import SwiftUI
import SwiftData
import AppKit

/// A dense, compact reading view: a slim header, a tight summary strip, and a
/// parallel board (To Do · Completed · Questions).
struct NoteDetailView: View {
    @Bindable var note: ReviewNote
    @State private var showExport = false

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
        .toolbar { exportToolbar }
        .sheet(isPresented: $showExport) { ExportSheet(note: note) }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var exportToolbar: some ToolbarContent {
        ToolbarSpacer(.flexible)
        ToolbarItem(placement: .primaryAction) {
            Button {
                showExport = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Copy or share this review")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .font(.system(size: 26, weight: .bold, design: .rounded))
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
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summaryStrip: some View {
        if !note.summary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Summary", systemImage: "text.alignleft")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(note.summary)
                    .font(.system(size: 13, design: .rounded))
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
                    .font(.system(size: 12, weight: .bold, design: .rounded))
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

/// Copy and share, combined: one modal with both export paths for the note's
/// agent-ready Markdown.
private struct ExportSheet: View {
    let note: ReviewNote
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        VStack(spacing: 16) {
            Label(note.title, systemImage: "doc.text")
                .font(.headline)
                .lineLimit(1)
            Text("Export this review as agent-ready Markdown — summary, verdict, action items with detail, and open questions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(MarkdownExporter.markdown(for: note), forType: .string)
                    withAnimation { didCopy = true }
                } label: {
                    Label(didCopy ? "Copied" : "Copy Markdown",
                          systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let url = try? MarkdownExporter.temporaryFileURL(for: note) {
                    ShareLink(item: url) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 380)
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
