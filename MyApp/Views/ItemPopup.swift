import SwiftUI
import SwiftData

/// Identifies which record a detail popup window shows. Value-based so the
/// popup `WindowGroup` can be opened with `openWindow(value:)`.
enum ItemPopupRef: Codable, Hashable {
    case actionItem(UUID)
    case question(UUID)
    case decision(UUID)
}

/// A standalone glass window showing one item's full detail. Fetches by UUID
/// so the window survives independently of the view that opened it.
struct ItemPopupWindowView: View {
    let ref: ItemPopupRef?
    @Environment(\.modelContext) private var context

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                Group {
                    switch ref {
                    case .actionItem(let id):
                        if let item = fetch(ActionItem.self, id: id) { ActionItemDetail(item: item) }
                        else { missing }
                    case .question(let id):
                        if let question = fetch(OpenQuestion.self, id: id) { QuestionDetail(question: question) }
                        else { missing }
                    case .decision(let id):
                        if let decision = fetch(Decision.self, id: id) { DecisionDetail(decision: decision) }
                        else { missing }
                    case nil:
                        missing
                    }
                }
                .padding(18)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 380, minHeight: 300)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private var missing: some View {
        Text("This item is no longer available.")
            .font(Theme.rounded(13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func fetch(_ type: ActionItem.Type, id: UUID) -> ActionItem? {
        var descriptor = FetchDescriptor<ActionItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetch(_ type: OpenQuestion.Type, id: UUID) -> OpenQuestion? {
        var descriptor = FetchDescriptor<OpenQuestion>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetch(_ type: Decision.Type, id: UUID) -> Decision? {
        var descriptor = FetchDescriptor<Decision>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

// MARK: - Action item detail

private struct ActionItemDetail: View {
    @Bindable var item: ActionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                PriorityBadge(priority: item.priority)
                CategoryChip(category: item.category)
                Spacer()
                Button {
                    item.isDone.toggle()
                } label: {
                    Label(item.isDone ? "Completed" : "Mark complete",
                          systemImage: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(Theme.rounded(12, .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.isDone ? Color(red: 0.35, green: 0.85, blue: 0.55) : .secondary)
            }

            Text(item.oneLiner)
                .font(Theme.display(19, .semibold))
                .strikethrough(item.isDone)
                .textSelection(.enabled)

            if !item.rationale.isEmpty {
                section("Why it matters", text: item.rationale, tint: item.priority.tint)
            }
            if !item.inDepthDetail.isEmpty {
                section("In depth", text: item.inDepthDetail, tint: nil)
            }
            if !item.supportingQuotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    header("From the discussion")
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
            if !item.attribution.isEmpty {
                Text("Raised by \(item.attribution)")
                    .font(Theme.rounded(11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private func section(_ title: String, text: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(title)
            Text(text)
                .font(Theme.rounded(13))
                .lineSpacing(3)
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary.opacity(0.9)))
                .textSelection(.enabled)
        }
    }
}

// MARK: - Question detail

private struct QuestionDetail: View {
    @Bindable var question: OpenQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                question.isResolved.toggle()
            } label: {
                Label(question.isResolved ? "Resolved" : "Mark resolved",
                      systemImage: question.isResolved ? "checkmark.circle.fill" : "circle")
                    .font(Theme.rounded(12, .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(question.isResolved ? Color(red: 0.35, green: 0.85, blue: 0.55) : .secondary)

            Text(question.text)
                .font(Theme.display(18, .semibold))
                .strikethrough(question.isResolved)
                .textSelection(.enabled)

            if !question.attribution.isEmpty {
                Text("Asked by \(question.attribution)")
                    .font(Theme.rounded(11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

// MARK: - Decision detail

private struct DecisionDetail: View {
    let decision: Decision

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Decision", systemImage: "checkmark.seal")
                .font(Theme.rounded(12, .bold))
                .foregroundStyle(.secondary)
            Text(decision.statement)
                .font(Theme.display(18, .semibold))
                .textSelection(.enabled)
            if !decision.attribution.isEmpty {
                Text("Decided by \(decision.attribution)")
                    .font(Theme.rounded(11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
