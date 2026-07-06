import SwiftUI

/// A compact action row for the dense board. Shows a priority dot + one-liner;
/// tap to progressively reveal depth (why → detail + evidence). Participates in
/// the drag-to-complete board with a small selection affordance.
struct ActionRow: View {
    let item: ActionItem
    var isSelected = false
    var onToggleSelect: () -> Void = {}

    @State private var depth = 0

    private var maxDepth: Int {
        if !item.inDepthDetail.isEmpty || !item.supportingQuotes.isEmpty { return 2 }
        if !item.rationale.isEmpty { return 1 }
        return 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: depth > 0 ? 8 : 0) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? Color.accentColor : .tertiary)
                }
                .buttonStyle(.plain)

                Circle()
                    .fill(item.priority.tint)
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)

                Text(item.oneLiner)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .lineLimit(depth > 0 ? nil : 2)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if maxDepth > 0 {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(depth > 0 ? 180 : 0))
                        .padding(.top, 3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { advance() }

            if depth >= 1, !item.rationale.isEmpty {
                Text(item.rationale)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(item.priority.tint.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 23)
            }

            if depth >= 2 {
                VStack(alignment: .leading, spacing: 6) {
                    if !item.inDepthDetail.isEmpty {
                        Text(item.inDepthDetail)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(item.supportingQuotes, id: \.self) { quote in
                        Text("“\(quote)”")
                            .font(.system(size: 11, design: .rounded).italic())
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                            .overlay(alignment: .leading) {
                                Capsule().fill(item.priority.tint.opacity(0.4)).frame(width: 2)
                            }
                    }
                    HStack(spacing: 8) {
                        PriorityBadge(priority: item.priority)
                        CategoryChip(category: item.category)
                    }
                }
                .padding(.leading, 23)
            }

            if maxDepth > 0 {
                Button(action: advance) {
                    Text(depth >= maxDepth ? "Less" : (depth == 0 ? "Why it matters" : "Go deeper"))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(item.priority.tint)
                }
                .buttonStyle(.plain)
                .padding(.leading, 23)
            }
        }
        .padding(10)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.05), lineWidth: isSelected ? 1.5 : 1)
        )
        .opacity(item.isDone ? 0.75 : 1)
    }

    private func advance() {
        withAnimation(.smooth(duration: 0.3)) {
            depth = depth >= maxDepth ? 0 : depth + 1
        }
    }
}
