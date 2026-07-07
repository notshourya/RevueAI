import SwiftUI
import SwiftData

/// The assistant's search-bar face for the toolbar: a glass capsule that
/// looks like a search field and anchors the query popover below itself.
struct AssistantSearchBar: View {
    @Binding var isPresented: Bool
    var assistant: ReviewAssistant

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Ask about your reviews…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(width: 280)
            .glassEffect(.regular, in: .capsule)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Ask the assistant about your reviews")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            AssistantPopoverView(assistant: assistant, isPresented: $isPresented)
        }
    }
}

/// The expanded assistant: query field on top (focused on open), suggestion
/// rows when the thread is empty, and the session thread below — every
/// surface liquid glass.
struct AssistantPopoverView: View {
    var assistant: ReviewAssistant
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var context
    @State private var question = ""
    @FocusState private var fieldFocused: Bool

    private static let suggestions = [
        "Which action items are still open?",
        "What did we decide recently?",
        "Summarize last week's reviews",
    ]

    var body: some View {
        Group {
            if assistant.isAvailable {
                content
            } else {
                unavailable
            }
        }
        .frame(width: 440)
        .presentationBackground(.clear)
    }

    private var content: some View {
        VStack(spacing: 10) {
            queryField
            if assistant.exchanges.isEmpty && !assistant.isThinking {
                suggestionRows
            }
            if !assistant.exchanges.isEmpty || assistant.isThinking {
                thread
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(8)
        .onAppear { fieldFocused = true }
    }

    // MARK: - Query field

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Ask about your reviews…", text: $question)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($fieldFocused)
                .onSubmit { submit(question) }
                .disabled(assistant.isThinking)
            if !assistant.exchanges.isEmpty {
                Button {
                    assistant.clear()
                    fieldFocused = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear the conversation")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }

    private func submit(_ text: String) {
        question = ""
        Task { await assistant.ask(text) }
    }

    // MARK: - Suggestions

    private var suggestionRows: some View {
        VStack(spacing: 4) {
            ForEach(Self.suggestions, id: \.self) { suggestion in
                Button {
                    submit(suggestion)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(suggestion)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .rect(cornerRadius: 10))
            }
        }
    }

    // MARK: - Thread

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(assistant.exchanges) { exchange in
                        ExchangeView(exchange: exchange) { noteID in
                            isPresented = false
                            openNote(id: noteID)
                        }
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

    /// Selects the cited note via the shell's notification (the popover has
    /// no direct handle on the selection binding).
    private func openNote(id: UUID) {
        NotificationCenter.default.post(name: .revueOpenNote, object: nil, userInfo: ["id": id])
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
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(8)
    }
}

extension Notification.Name {
    /// Posted with userInfo ["id": UUID] to select a note in the shell.
    static let revueOpenNote = Notification.Name("revueOpenNote")
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
