import Foundation
import Observation
import CoreGraphics

/// Layout state for the three-panel shell: per-panel width fractions,
/// collapse state, and divider dragging — persisted across launches.
@MainActor
@Observable
final class PanelLayoutModel {
    enum Panel: String, CaseIterable {
        case library, reader, live
    }

    /// No visible panel may shrink below this share of the stored total.
    static let minFraction: CGFloat = 0.18

    private static let fractionsKey = "shell.panelFractions"
    private static let collapsedKey = "shell.collapsedPanels"

    private(set) var fractions: [CGFloat]
    private(set) var collapsed: Set<Panel>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.array(forKey: Self.fractionsKey) as? [Double], stored.count == 3 {
            fractions = stored.map { CGFloat($0) }
        } else {
            fractions = [0.28, 0.44, 0.28]
        }
        let names = defaults.stringArray(forKey: Self.collapsedKey) ?? []
        collapsed = Set(names.compactMap(Panel.init(rawValue:)))
    }

    var visiblePanels: [Panel] { Panel.allCases.filter { !collapsed.contains($0) } }

    func isCollapsed(_ panel: Panel) -> Bool { collapsed.contains(panel) }

    /// The panel's width share among currently visible panels (sums to 1).
    func fraction(for panel: Panel) -> CGFloat {
        guard !isCollapsed(panel) else { return 0 }
        let visibleTotal = visiblePanels.reduce(CGFloat(0)) { $0 + fractions[index(of: $1)] }
        guard visibleTotal > 0 else { return 1 / CGFloat(max(1, visiblePanels.count)) }
        return fractions[index(of: panel)] / visibleTotal
    }

    /// Drags the divider between `panel` and the next visible panel. The drag
    /// is rejected (not clamped) when either side would fall below minimum,
    /// which is fine interactively because drags arrive as small deltas.
    func dragDivider(after panel: Panel, deltaFraction: CGFloat) {
        let visible = visiblePanels
        guard let position = visible.firstIndex(of: panel), position + 1 < visible.count else { return }
        let left = index(of: visible[position])
        let right = index(of: visible[position + 1])
        let proposedLeft = fractions[left] + deltaFraction
        let proposedRight = fractions[right] - deltaFraction
        guard proposedLeft >= Self.minFraction, proposedRight >= Self.minFraction else { return }
        fractions[left] = proposedLeft
        fractions[right] = proposedRight
        persist()
    }

    /// Collapses or expands a panel; the last visible panel can't collapse.
    func toggleCollapse(_ panel: Panel) {
        if collapsed.contains(panel) {
            collapsed.remove(panel)
        } else {
            guard visiblePanels.count > 1 else { return }
            collapsed.insert(panel)
        }
        persist()
    }

    /// Ensures the live panel is visible (called when capture starts).
    func expandLive() {
        guard collapsed.contains(.live) else { return }
        collapsed.remove(.live)
        persist()
    }

    private func index(of panel: Panel) -> Int { Panel.allCases.firstIndex(of: panel)! }

    private func persist() {
        defaults.set(fractions.map(Double.init), forKey: Self.fractionsKey)
        defaults.set(collapsed.map(\.rawValue).sorted(), forKey: Self.collapsedKey)
    }
}
