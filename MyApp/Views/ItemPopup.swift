import SwiftUI
import SwiftData

// Detail content for extracted items, shown in popovers anchored to their
// rows (action items, open questions, decisions).

// MARK: - Action item detail

struct ActionItemDetail: View {
    @Bindable var item: ActionItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""
    @State private var allTags: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Picker("Priority", selection: $item.priority) {
                        ForEach(ActionPriority.allCases) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Picker("Category", selection: $item.category) {
                        ForEach(ActionCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Button {
                        item.isDone.toggle()
                    } label: {
                        Label(item.isDone ? "Completed" : "Mark complete",
                              systemImage: item.isDone ? "checkmark.circle.fill" : "circle")
                            .font(Theme.rounded(12, .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(item.isDone ? Theme.success : .secondary)
                }

                TextField("What needs to happen", text: $item.oneLiner, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.display(17, .semibold))

                if !item.rationale.isEmpty {
                    DetailSection(title: "Why it matters", text: item.rationale, tint: item.priority.tint)
                }

                VStack(alignment: .leading, spacing: 6) {
                    DetailHeader(title: "In depth")
                    TextField("Add detail", text: $item.inDepthDetail, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Theme.rounded(13))
                }

                tagEditor

                if !item.supportingQuotes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        DetailHeader(title: "From the discussion")
                        ForEach(item.supportingQuotes, id: \.self) { quote in
                            Text("“\(quote)”")
                                .font(Theme.rounded(12).italic())
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(item.priority.tint.opacity(0.4)).frame(width: 2)
                                }
                        }
                    }
                }

                HStack {
                    if !item.attribution.isEmpty {
                        Text("Raised by \(item.attribution)")
                            .font(Theme.rounded(11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        dismiss()
                        context.delete(item)
                        try? context.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(Theme.rounded(11, .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.85))
                }
            }
            .padding(16)
        }
        .frame(width: 380)
        .frame(maxHeight: 480)
        .onAppear { allTags = ActionItem.allTags(in: context) }
        .onChange(of: item.oneLiner) { markEdited() }
        .onChange(of: item.inDepthDetail) { markEdited() }
        .onChange(of: item.priority) { markEdited() }
        .onChange(of: item.category) { markEdited() }
        .onChange(of: item.tags) { markEdited() }
    }

    private func markEdited() {
        if !item.userModified { item.userModified = true }
        try? context.save()
    }

    // MARK: - Tags

    private var suggestions: [String] {
        guard !newTag.isEmpty else { return [] }
        return allTags.filter { $0.localizedCaseInsensitiveContains(newTag) && !item.tags.contains($0) }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailHeader(title: "Tags")
            FlowLayoutish {
                ForEach(item.tags, id: \.self) { tag in
                    HStack(spacing: 3) {
                        Text(tag)
                        Button {
                            item.tags.removeAll { $0 == tag }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .font(Theme.rounded(11, .medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.24), lineWidth: 1))
                    .foregroundStyle(Theme.accent)
                }
                TextField("Add tag", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(Theme.rounded(11))
                    .frame(minWidth: 60, maxWidth: 100)
                    .onSubmit { addTag(newTag) }
            }
            if !suggestions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(suggestions.prefix(4), id: \.self) { suggestion in
                        Button(suggestion) { addTag(suggestion) }
                            .buttonStyle(.plain)
                            .font(Theme.rounded(11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func addTag(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !item.tags.contains(tag) else { newTag = ""; return }
        item.tags.append(tag)
        newTag = ""
    }
}

/// A minimal wrapping layout for tag chips.
struct FlowLayoutish: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(proposal: proposal, subviews: subviews)
        for (subview, position) in zip(subviews, arrangement.positions) {
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                          proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? 340
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + 6
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + 6
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

// MARK: - Question detail

struct QuestionDetail: View {
    @Bindable var question: OpenQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                question.isResolved.toggle()
            } label: {
                Label(question.isResolved ? "Resolved" : "Mark resolved",
                      systemImage: question.isResolved ? "checkmark.circle.fill" : "circle")
                    .font(Theme.rounded(12, .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(question.isResolved ? Theme.success : .secondary)

            Text(question.text)
                .font(Theme.display(16, .semibold))
                .strikethrough(question.isResolved)
                .textSelection(.enabled)

            if !question.attribution.isEmpty {
                Text("Asked by \(question.attribution)")
                    .font(Theme.rounded(11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

// MARK: - Decision detail

struct DecisionDetail: View {
    let decision: Decision

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Decision", systemImage: "checkmark.seal")
                .font(Theme.rounded(12, .bold))
                .foregroundStyle(.secondary)
            Text(decision.statement)
                .font(Theme.display(16, .semibold))
                .textSelection(.enabled)
            if !decision.attribution.isEmpty {
                Text("Decided by \(decision.attribution)")
                    .font(Theme.rounded(11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

// MARK: - Shared pieces

struct DetailHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

struct DetailSection: View {
    let title: String
    let text: String
    let tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailHeader(title: title)
            Text(text)
                .font(Theme.rounded(13))
                .lineSpacing(3)
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary.opacity(0.9)))
                .textSelection(.enabled)
        }
    }
}
