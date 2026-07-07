import SwiftUI
import SwiftData

/// The collapsed assistant: a floating glass search pill, pinned top-center
/// of the content area (Apple Music style). Clicking expands the card.
struct AssistantSearchPill: View {
    var onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Ask about your reviews…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("⌘K")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(width: 320)
            .glassEffect(.regular, in: .capsule)
            .overlay(Capsule().strokeBorder(.secondary.opacity(0.25), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("k", modifiers: .command)
        .help("Ask the assistant about your reviews (⌘K)")
    }
}

/// The expanded assistant: query field on top (auto-focused), suggestions
/// while the thread is empty, the session thread below — all liquid glass.
struct AssistantResultsCard: View {
    var assistant: ReviewAssistant
    var suggestions: [String] = []
    /// When the input lives in the native toolbar search field, the card
    /// hides its own field and shows only suggestions/answers.
    var showsField: Bool = true
    var onAsk: (String) -> Void
    var onOpenNote: (UUID) -> Void
    var onClose: () -> Void

    @State private var question = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            if showsField {
                fieldRow
            } else {
                headerRow
            }

            if !assistant.isAvailable {
                unavailable
            } else if assistant.exchanges.isEmpty && !assistant.isThinking {
                suggestionRows
            } else {
                thread
            }
        }
        .padding(14)
        .frame(width: 560)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(.top, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear { if showsField { fieldFocused = true } }
        .onExitCommand(perform: onClose)
    }

    private var fieldRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Ask about your reviews…", text: $question)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($fieldFocused)
                .onSubmit {
                    let text = question
                    question = ""
                    onAsk(text)
                }
                .disabled(assistant.isThinking)
            trailingButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Label("Assistant", systemImage: "sparkles")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            trailingButtons
        }
    }

    @ViewBuilder
    private var trailingButtons: some View {
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
        .help("Close (Esc)")
    }

    private var suggestionRows: some View {
        VStack(spacing: 4) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    onAsk(suggestion)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(suggestion)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .rect(cornerRadius: 10))
            }
        }
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
