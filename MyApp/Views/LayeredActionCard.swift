import SwiftUI

/// A compact action row for the dense board: priority dot + one-liner +
/// selection affordance. Clicking the row opens the item's detail in its own
/// glass popup window. Participates in the drag-to-complete board.
struct ActionRow: View {
    let item: ActionItem
    var isSelected = false
    var onToggleSelect: () -> Void = {}

    @State private var showDetail = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)

            Circle()
                .fill(item.priority.tint)
                .frame(width: 7, height: 7)
                .padding(.top, 4)

            Text(item.oneLiner)
                .font(Theme.rounded(13, .medium))
                .lineLimit(2)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
        }
        .padding(10)
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail, arrowEdge: .trailing) {
            ActionItemDetail(item: item)
        }
        .glassEffect(isSelected ? .regular.tint(Theme.accent.opacity(0.3)) : .regular, in: .rect(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 1.5)
        )
        .opacity(item.isDone ? 0.75 : 1)
        .help("Show details")
    }
}
