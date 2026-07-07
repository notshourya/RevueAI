import SwiftUI
import SwiftData

/// The assistant's answer surface: a liquid-glass card dropped below the
/// toolbar (Apple Music search style) showing the session thread.
struct AssistantResultsCard: View {
    var assistant: ReviewAssistant
    var onOpenNote: (UUID) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Assistant", systemImage: "sparkles")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
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
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close")
            }

            if assistant.isAvailable {
                thread
            } else {
                unavailable
            }
        }
        .padding(14)
        .frame(width: 480)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(.top, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
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
            }
            .frame(maxHeight: 380)
            .onChange(of: assistant.exchanges.count) {
                withAnimation { proxy.scrollTo(assistant.exchanges.last?.id, anchor: .bottom) }
            }
            .onChange(of: assistant.isThinking) { _, thinking in
                if thinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Text("Apple Intelligence is off")
                .font(.headline)
            Text("Turn it on in System Settings to ask questions about your reviews.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
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
                                .glassEffect(.regular, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .help("Open this note")
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
