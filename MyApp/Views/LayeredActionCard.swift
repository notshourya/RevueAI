import SwiftUI

/// A compact action row for the dense board: priority dot + one-liner +
/// selection affordance. Clicking the row opens the item's detail in its own
/// glass popup window. Participates in the drag-to-complete board.
struct ActionRow: View {
    let item: ActionItem
    var isSelected = false
    var onToggleSelect: () -> Void = {}
    var showDetailOnAppear = false

    @State private var showDetail = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
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

            if item.userModified || item.isUserCreated {
                Circle()
                    .fill(Theme.warm.opacity(0.9))
                    .frame(width: 5, height: 5)
                    .padding(.top, 5)
                    .help("Edited by you — polish won't overwrite it")
            }

            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .popover(isPresented: $showDetail, arrowEdge: .trailing) {
            ActionItemDetail(item: item)
        }
        .onAppear { if showDetailOnAppear { showDetail = true } }
        .background(isSelected ? Theme.accent.opacity(0.15) : Color.clear)
        .opacity(item.isDone ? 0.75 : 1)
        .help("Show details")
    }
}
