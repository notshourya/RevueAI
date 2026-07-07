import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Lightweight drag payload identifying an action item by id.
struct ActionItemTransfer: Codable, Transferable, Identifiable, Sendable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// A dense, parallel board for a review: **To Do · Completed · Questions** as
/// side-by-side columns. Action items are completed by dragging their rows
/// between the first two columns (multi-select supported). Compact and skinny.
struct ReviewBoard: View {
    let note: ReviewNote

    @Environment(\.modelContext) private var context
    @State private var selection: Set<UUID> = []

    private var openItems: [ActionItem] { note.sortedActionItems.filter { !$0.isDone } }
    private var doneItems: [ActionItem] { note.sortedActionItems.filter { $0.isDone } }
    private var questions: [OpenQuestion] { note.sortedOpenQuestions }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !selection.isEmpty { selectionBar }

            HStack(alignment: .top, spacing: 12) {
                actionColumn("To Do", systemImage: "circle.dashed",
                             items: openItems, markCompleted: false,
                             emptyText: "No open items.")
                actionColumn("Completed", systemImage: "checkmark.circle.fill",
                             items: doneItems, markCompleted: true,
                             emptyText: "Drag items here.")
                questionsColumn
            }
        }
        .dragContainer(for: ActionItemTransfer.self, itemID: \.id) { ids in
            ids.map { ActionItemTransfer(id: $0) }
        }
        .dragContainerSelection(Array(selection))
    }

    // MARK: - Selection bar

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text("\(selection.count) selected")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer()
            Button("Complete") { apply(Array(selection), done: true) }
            Button("Reopen") { apply(Array(selection), done: false) }
            Button("Clear") { withAnimation { selection.removeAll() } }
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .transition(.opacity)
    }

    // MARK: - Columns

    private func actionColumn(_ title: String, systemImage: String, items: [ActionItem], markCompleted: Bool, emptyText: String) -> some View {
        BoardColumn(title: title, systemImage: systemImage, count: items.count,
                    accent: markCompleted ? Color(red: 0.35, green: 0.85, blue: 0.55) : .secondary,
                    isEmpty: items.isEmpty, emptyText: emptyText,
                    dropAction: { ids in apply(ids, done: markCompleted) }) {
            ForEach(items) { item in
                ActionRow(item: item, isSelected: selection.contains(item.id)) {
                    toggleSelect(item.id)
                }
                .draggable(containerItemID: item.id)
                .contextMenu {
                    Button(item.isDone ? "Reopen" : "Mark complete") { apply([item.id], done: !item.isDone) }
                    Button(selection.contains(item.id) ? "Deselect" : "Select") { toggleSelect(item.id) }
                }
            }
        }
    }

    private var questionsColumn: some View {
        BoardColumn(title: "Questions", systemImage: "questionmark.circle", count: questions.count,
                    accent: .secondary, isEmpty: questions.isEmpty, emptyText: "No open questions.",
                    dropAction: nil) {
            ForEach(questions) { question in
                QuestionRow(question: question)
            }
        }
    }

    // MARK: - Mutations

    private func toggleSelect(_ id: UUID) {
        withAnimation(.snappy) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        }
    }

    private func apply(_ ids: [UUID], done: Bool) {
        let byID = Dictionary(uniqueKeysWithValues: (note.actionItems ?? []).map { ($0.id, $0) })
        withAnimation(.smooth) {
            for id in ids { byID[id]?.isDone = done }
            selection.removeAll()
        }
        try? context.save()
    }
}

// MARK: - Board column

private struct BoardColumn<Content: View>: View {
    let title: String
    let systemImage: String
    let count: Int
    let accent: Color
    let isEmpty: Bool
    let emptyText: String
    /// When non-nil, the column accepts dropped action items.
    let dropAction: (([UUID]) -> Void)?
    @ViewBuilder var content: Content

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
                Text("\(count)").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.tertiary)
                Spacer()
            }

            if isEmpty {
                Text(emptyText)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 8) { content }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isTargeted ? 0.08 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : .white.opacity(0.05),
                              style: StrokeStyle(lineWidth: isTargeted ? 1.5 : 1, dash: isTargeted ? [5] : []))
        )
        .animation(.smooth(duration: 0.2), value: isTargeted)
        .modifier(DropIfNeeded(dropAction: dropAction, isTargeted: $isTargeted))
    }
}

/// Applies a drop destination only when the column accepts drops.
private struct DropIfNeeded: ViewModifier {
    let dropAction: (([UUID]) -> Void)?
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        if let dropAction {
            content.dropDestination(for: ActionItemTransfer.self) { transfers, _ in
                dropAction(transfers.map(\.id))
                return true
            } isTargeted: { isTargeted = $0 }
        } else {
            content
        }
    }
}

// MARK: - Compact question row

private struct QuestionRow: View {
    @Bindable var question: OpenQuestion
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                question.isResolved.toggle()
            } label: {
                Image(systemName: question.isResolved ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(question.isResolved ? AnyShapeStyle(Color(red: 0.35, green: 0.85, blue: 0.55)) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(question.text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .strikethrough(question.isResolved)
                    .foregroundStyle(question.isResolved ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !question.attribution.isEmpty {
                    Text(question.attribution)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { openWindow(value: ItemPopupRef.question(question.id)) }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 11))
        .opacity(question.isResolved ? 0.75 : 1)
    }
}
