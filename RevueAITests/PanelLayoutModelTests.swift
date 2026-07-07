import Foundation
import Testing
@testable import RevueAI

@MainActor
struct PanelLayoutModelTests {
    private func makeDefaults() -> UserDefaults {
        let name = "PanelLayoutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultLayoutShowsThreePanels() {
        let model = PanelLayoutModel(defaults: makeDefaults())
        #expect(model.visiblePanels == [.library, .reader, .live])
        #expect(abs(model.fraction(for: .reader) - 0.44) < 0.001)
    }

    @Test func dragMovesWidthBetweenNeighbors() {
        let model = PanelLayoutModel(defaults: makeDefaults())
        model.dragDivider(after: .library, deltaFraction: 0.05)
        #expect(abs(model.fraction(for: .library) - 0.33) < 0.001)
        #expect(abs(model.fraction(for: .reader) - 0.39) < 0.001)
        #expect(abs(model.fraction(for: .live) - 0.28) < 0.001)
    }

    @Test func dragRejectsBelowMinimumWidth() {
        let model = PanelLayoutModel(defaults: makeDefaults())
        model.dragDivider(after: .library, deltaFraction: -0.5)
        #expect(abs(model.fraction(for: .library) - 0.28) < 0.001)
    }

    @Test func collapseHidesPanelAndRenormalizes() {
        let model = PanelLayoutModel(defaults: makeDefaults())
        model.toggleCollapse(.live)
        #expect(model.visiblePanels == [.library, .reader])
        #expect(model.isCollapsed(.live))
        let total = model.fraction(for: .library) + model.fraction(for: .reader)
        #expect(abs(total - 1.0) < 0.001)
    }

    @Test func lastVisiblePanelCannotCollapse() {
        let model = PanelLayoutModel(defaults: makeDefaults())
        model.toggleCollapse(.library)
        model.toggleCollapse(.reader)
        model.toggleCollapse(.live)
        #expect(model.visiblePanels == [.live])
    }

    @Test func expandLiveUncollapses() {
        let model = PanelLayoutModel(defaults: makeDefaults())
        model.toggleCollapse(.live)
        model.expandLive()
        #expect(!model.isCollapsed(.live))
    }

    @Test func layoutPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let first = PanelLayoutModel(defaults: defaults)
        first.dragDivider(after: .library, deltaFraction: 0.05)
        first.toggleCollapse(.live)
        let second = PanelLayoutModel(defaults: defaults)
        #expect(second.isCollapsed(.live))
        #expect(abs(second.fraction(for: .library) - 0.33 / 0.72) < 0.01)
    }
}
