import SwiftUI

/// Lays out the shell's panels side by side per `PanelLayoutModel`: visible
/// panels get their fraction of the remaining width, separated by draggable
/// dividers; collapsed panels shrink to a slim rail that re-expands on click.
struct PanelSplitView<Content: View>: View {
    var model: PanelLayoutModel
    @ViewBuilder var panelContent: (PanelLayoutModel.Panel) -> Content

    private static var railWidth: CGFloat { 32 }
    private static var dividerWidth: CGFloat { 9 }

    var body: some View {
        GeometryReader { geo in
            let visible = model.visiblePanels
            let railTotal = CGFloat(PanelLayoutModel.Panel.allCases.count - visible.count) * Self.railWidth
            let dividerTotal = CGFloat(max(0, visible.count - 1)) * Self.dividerWidth
            let panelWidth = max(0, geo.size.width - railTotal - dividerTotal)

            HStack(spacing: 0) {
                ForEach(PanelLayoutModel.Panel.allCases, id: \.self) { panel in
                    if model.isCollapsed(panel) {
                        CollapsedRail(panel: panel) { model.toggleCollapse(panel) }
                            .frame(width: Self.railWidth)
                    } else {
                        panelContent(panel)
                            .frame(width: panelWidth * model.fraction(for: panel))
                        if let last = visible.last, panel != last {
                            PanelDivider(panel: panel, model: model, panelWidth: panelWidth)
                                .frame(width: Self.dividerWidth)
                        }
                    }
                }
            }
            .animation(.smooth(duration: 0.25), value: model.visiblePanels)
        }
    }
}

/// The draggable gap between two visible panels.
private struct PanelDivider: View {
    let panel: PanelLayoutModel.Panel
    var model: PanelLayoutModel
    let panelWidth: CGFloat

    @State private var lastTranslation: CGFloat = 0
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(.white.opacity(hovering ? 0.35 : 0.12))
                .frame(width: 3, height: 44)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let delta = (value.translation.width - lastTranslation) / max(panelWidth, 1)
                    model.dragDivider(after: panel, deltaFraction: delta)
                    lastTranslation = value.translation.width
                }
                .onEnded { _ in lastTranslation = 0 }
        )
    }
}

/// A collapsed panel's slim rail — icon button that re-expands it.
private struct CollapsedRail: View {
    let panel: PanelLayoutModel.Panel
    var onExpand: () -> Void

    private var systemImage: String {
        switch panel {
        case .library: "books.vertical"
        case .reader: "doc.text"
        case .live: "waveform"
        }
    }

    var body: some View {
        Button(action: onExpand) {
            VStack {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .help("Expand panel")
    }
}
