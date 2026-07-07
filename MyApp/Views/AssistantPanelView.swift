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
