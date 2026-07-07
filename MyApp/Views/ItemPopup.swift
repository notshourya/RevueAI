import SwiftUI
import SwiftData

// Detail content for extracted items, shown in popovers anchored to their
// rows (action items, open questions, decisions).

// MARK: - Action item detail

struct ActionItemDetail: View {
    @Bindable var item: ActionItem

    var body: some View {
        ScrollView {
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
                    .font(Theme.display(17, .semibold))
                    .strikethrough(item.isDone)
                    .textSelection(.enabled)

                if !item.rationale.isEmpty {
                    DetailSection(title: "Why it matters", text: item.rationale, tint: item.priority.tint)
                }
                if !item.inDepthDetail.isEmpty {
                    DetailSection(title: "In depth", text: item.inDepthDetail, tint: nil)
                }
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
                if !item.attribution.isEmpty {
                    Text("Raised by \(item.attribution)")
                        .font(Theme.rounded(11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
        }
        .frame(width: 380)
        .frame(maxHeight: 440)
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
            .foregroundStyle(question.isResolved ? Color(red: 0.35, green: 0.85, blue: 0.55) : .secondary)

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
