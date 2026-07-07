# RevueAI UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild RevueAI's main window as three parallel resizable glass panels, add glass popup windows for item details, unify the recording orb into a state-driven brand component with a floating always-on-top presence, and add TourKit first-run onboarding plus an orb app icon.

**Architecture:** A `PanelLayoutModel` (pure, testable) drives a custom `PanelSplitView` that replaces `NavigationSplitView`. Item detail popups are value-based `WindowGroup` windows keyed by `ItemPopupRef`. A pure `OrbState` machine maps `CaptureCoordinator` state to one `OrbView` used everywhere; an AppKit `FloatingOrbController` shows it in a borderless `NSPanel` during capture. Onboarding embeds TourKit's slideshow in a sheet, followed by a permissions step. No pipeline changes.

**Tech Stack:** SwiftUI (macOS 27 SDK, `.glassEffect()`), AppKit (`NSPanel`), SwiftData, Swift Testing, TourKit (SPM), CoreGraphics (icon script).

## Global Constraints

- **Toolchain:** every `xcodebuild` invocation MUST be prefixed with `DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer` — the system Xcode 26.5 lacks the macOS 27 SDK and the build fails without it.
- **Test command (used in every task):**
  `DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' 2>&1 | grep -E "Test run|error:|TEST"`
  Success looks like `Test run with N tests in M suites passed` + `** TEST SUCCEEDED **`. Do not use `-quiet` (it suppresses the success line on this toolchain).
- **Existing tests stay green:** the suite currently has 43 tests in 7 suites. Every task ends with the full suite passing.
- **No pipeline changes:** files under `MyApp/AI/` and `MyApp/Capture/` must not change, except the single additive `isExtracting` property on `CaptureCoordinator` in Task 4.
- **Synced groups:** the Xcode project uses `PBXFileSystemSynchronizedRootGroup` — new `.swift` files under `MyApp/` or `RevueAITests/` are picked up automatically; do NOT add file references to `project.pbxproj`. The only pbxproj edits in this plan are the SPM package (Task 6) and app-icon build setting (Task 7).
- **Glass is presentation-only:** new chrome must check `accessibilityReduceTransparency` and fall back to an opaque fill; the orb must check `accessibilityReduceMotion` and render statically.
- **Design language:** near-black backdrop (`PremiumBackground`), rounded SF fonts via `Theme.rounded`/`Theme.display`, glass via `.glassEffect(.regular, in:)`. Match existing code style (`MyApp/Views/Components.swift`).

---

### Task 1: PanelLayoutModel

The pure layout state behind the three-panel shell: width fractions, collapse state, divider dragging with minimum widths, persistence, and `expandLive()`.

**Files:**
- Create: `MyApp/Views/Shell/PanelLayoutModel.swift`
- Create: `RevueAITests/PanelLayoutModelTests.swift`

**Interfaces:**
- Consumes: nothing (Foundation/Observation only).
- Produces: `PanelLayoutModel` (`@MainActor @Observable` class) with `enum Panel: String, CaseIterable { case library, reader, live }`, `init(defaults: UserDefaults = .standard)`, `var visiblePanels: [Panel]`, `func isCollapsed(_:) -> Bool`, `func fraction(for:) -> CGFloat` (renormalized over visible panels), `func dragDivider(after: Panel, deltaFraction: CGFloat)`, `func toggleCollapse(_:)`, `func expandLive()`. Task 2 consumes all of these.

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/PanelLayoutModelTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run the Global Constraints test command.
Expected: build error — `cannot find 'PanelLayoutModel' in scope`.

- [ ] **Step 3: Implement the model**

Create `MyApp/Views/Shell/PanelLayoutModel.swift`:

```swift
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
            fractions = stored.map(CGFloat.init)
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Global Constraints test command.
Expected: `Test run with 50 tests in 8 suites passed` (43 existing + 7 new), `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyApp/Views/Shell RevueAITests/PanelLayoutModelTests.swift
git commit -m "feat: panel layout model for the three-panel shell"
```

---

### Task 2: Glass shell — PanelSplitView, PanelChrome, RootShellView, LivePanelView

Replaces the `NavigationSplitView` main window with three parallel glass panels (Library | Reader | Live) with draggable dividers and collapse rails.

**Files:**
- Create: `MyApp/Views/Shell/PanelChrome.swift`
- Create: `MyApp/Views/Shell/PanelSplitView.swift`
- Create: `MyApp/Views/Shell/RootShellView.swift`
- Create: `MyApp/Views/LivePanelView.swift`
- Rewrite: `MyApp/Views/LibraryView.swift` (struct becomes `LibraryPane`, split-view wrapper removed)
- Modify: `MyApp/RevueAIApp.swift:32-41` (window shows `RootShellView`)

**Interfaces:**
- Consumes: `PanelLayoutModel` (Task 1), `CaptureCoordinator` (`state`, `isActive`, `elapsedText`, `capturedPhraseCount`, `livePoints`, `recentTranscript`, `start/pause/resume/stop`), existing `PremiumBackground`, `Theme`, `RecordOrb`, `StateOrb`, `NoteDetailView`, `VerdictBadge`.
- Produces: `RootShellView` (the window root), `LibraryPane(selection: Binding<ReviewNote?>)`, `LivePanelView()`, `PanelChrome(title:systemImage:onCollapse:accessory:content:)`, `PanelSplitView(model:panelContent:)`. Task 3 adds popups on top; Tasks 4–6 modify `RootShellView` and `LivePanelView`.

- [ ] **Step 1: Create PanelChrome**

Create `MyApp/Views/Shell/PanelChrome.swift`:

```swift
import SwiftUI

/// Standard chrome for one shell panel: a slim header (icon label, optional
/// accessory, collapse control) over the panel's content, on one glass
/// surface. Falls back to an opaque fill when transparency is reduced.
struct PanelChrome<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    var onCollapse: () -> Void
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(Theme.rounded(12, .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                accessory
                Button(action: onCollapse) {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(90))
                }
                .buttonStyle(.plain)
                .help("Collapse panel")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .modifier(PanelSurface(reduceTransparency: reduceTransparency))
    }
}

/// Glass panel surface with an opaque accessibility fallback.
private struct PanelSurface: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(white: 0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    )
            )
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }
}
```

- [ ] **Step 2: Create PanelSplitView**

Create `MyApp/Views/Shell/PanelSplitView.swift`:

```swift
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
```

- [ ] **Step 3: Rewrite LibraryView.swift as LibraryPane**

Replace the entire contents of `MyApp/Views/LibraryView.swift` with:

```swift
import SwiftUI
import SwiftData

enum LibraryLayout: String { case list, grid }

/// The library panel — reviews as List or masonry Grid with a controls row on
/// top and the record dock at the bottom. Selection is owned by the shell.
struct LibraryPane: View {
    @Environment(\.modelContext) private var context
    @Environment(CaptureCoordinator.self) private var coordinator
    @Query(sort: \ReviewNote.date, order: .reverse) private var notes: [ReviewNote]

    @Binding var selection: ReviewNote?

    @AppStorage("libraryLayout") private var layoutRaw = LibraryLayout.list.rawValue
    @State private var showArchived = false

    private var layout: LibraryLayout { LibraryLayout(rawValue: layoutRaw) ?? .list }
    private var shownNotes: [ReviewNote] { notes.filter { $0.isArchived == showArchived } }

    var body: some View {
        VStack(spacing: 0) {
            controlsRow
            Group {
                if shownNotes.isEmpty { emptyState }
                else {
                    switch layout {
                    case .list: listView
                    case .grid: gridView
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { recordBar }
        .onChange(of: shownNotes.count) {
            if selection == nil || !shownNotes.contains(where: { $0 == selection }) {
                selection = shownNotes.first
            }
        }
        .onChange(of: coordinator.state) { _, newValue in
            if newValue == .idle { selection = shownNotes.first }
        }
        .onChange(of: showArchived) { selection = shownNotes.first }
        .onAppear { selection = selection ?? shownNotes.first }
    }

    // MARK: - Controls row

    private var controlsRow: some View {
        HStack(spacing: 10) {
            Text(showArchived ? "Archived" : "Reviews")
                .font(Theme.display(20))
            Spacer()
            Picker("Layout", selection: $layoutRaw) {
                Image(systemName: "list.bullet").tag(LibraryLayout.list.rawValue)
                Image(systemName: "square.grid.2x2").tag(LibraryLayout.grid.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(width: 88)
            .help("Switch between list and grid")
            Button {
                withAnimation(.smooth) { showArchived.toggle() }
            } label: {
                Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(showArchived ? "Show active reviews" : "Show archived reviews")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    // MARK: - List

    private var listView: some View {
        List(selection: $selection) {
            ForEach(shownNotes) { note in
                NoteRow(note: note)
                    .tag(note)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 5, leading: 12, bottom: 5, trailing: 12))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { delete(note) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { archive(note) } label: {
                            Label(note.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                        }
                        .tint(.orange)
                    }
                    .contextMenu { rowMenu(note) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    // MARK: - Grid

    private var gridView: some View {
        GeometryReader { geo in
            let columnCount = max(2, Int(geo.size.width / 190))
            let columns = distributed(into: columnCount)
            ScrollView {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<columns.count, id: \.self) { col in
                        VStack(spacing: 12) {
                            ForEach(columns[col]) { note in
                                NoteCard(note: note, isSelected: selection == note)
                                    .onTapGesture { selection = note }
                                    .contextMenu { rowMenu(note) }
                            }
                        }
                    }
                }
                .padding(14)
            }
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
    }

    /// Greedy masonry: place each review into the currently-shortest column so
    /// heights stay balanced and cards stagger like the Shortcuts grid.
    private func distributed(into columnCount: Int) -> [[ReviewNote]] {
        var cols = Array(repeating: [ReviewNote](), count: columnCount)
        var heights = Array(repeating: CGFloat(0), count: columnCount)
        for note in shownNotes {
            let target = heights.firstIndex(of: heights.min() ?? 0) ?? 0
            cols[target].append(note)
            heights[target] += estimatedHeight(note)
        }
        return cols
    }

    private func estimatedHeight(_ note: ReviewNote) -> CGFloat {
        let titleLines = min(3, max(1, note.title.count / 18 + 1))
        let bodyLines = note.summary.isEmpty ? 0 : min(6, note.summary.count / 22 + 1)
        return CGFloat(64 + titleLines * 20 + bodyLines * 15)
    }

    @ViewBuilder
    private func rowMenu(_ note: ReviewNote) -> some View {
        Button { archive(note) } label: {
            Label(note.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
        }
        Button(role: .destructive) { delete(note) } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Record dock

    private var recordBar: some View {
        VStack(spacing: 8) {
            if coordinator.isActive {
                Text(coordinator.state == .paused
                     ? "Paused · \(coordinator.elapsedText)"
                     : "\(coordinator.elapsedText) · \(coordinator.capturedPhraseCount) phrases")
                    .font(Theme.rounded(12, .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            RecordOrb(isActive: coordinator.isActive, size: 54, disabled: coordinator.state == .processing) {
                toggleCapture()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: showArchived ? "archivebox" : "waveform")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(showArchived ? "No archived reviews" : "No reviews yet")
                .font(Theme.display(20))
            if !showArchived {
                Text("Press Record below to capture your first review.")
                    .font(Theme.rounded(13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func toggleCapture() {
        Task {
            if coordinator.isActive { await coordinator.stop() }
            else { await coordinator.start(context: context) }
        }
    }

    private func archive(_ note: ReviewNote) {
        withAnimation(.smooth) { note.isArchived.toggle() }
        try? context.save()
    }

    private func delete(_ note: ReviewNote) {
        withAnimation(.smooth) { context.delete(note) }
        try? context.save()
    }
}

// MARK: - List row

private struct NoteRow: View {
    let note: ReviewNote

    private var itemCount: Int { note.actionItems?.count ?? 0 }
    private var openCount: Int { (note.openQuestions ?? []).filter { !$0.isResolved }.count }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(note.verdict.tint)
                .frame(width: 5, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text(note.title)
                    .font(Theme.display(16, .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    VerdictBadge(verdict: note.verdict)
                    if itemCount > 0 { Label("\(itemCount)", systemImage: "checklist") }
                    if openCount > 0 { Label("\(openCount)", systemImage: "questionmark.circle") }
                }
                .font(Theme.rounded(11, .medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

// MARK: - Grid card

private struct NoteCard: View {
    let note: ReviewNote
    var isSelected = false

    private var itemCount: Int { note.actionItems?.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { VerdictBadge(verdict: note.verdict); Spacer() }
            Text(note.title)
                .font(Theme.display(15, .semibold))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                if itemCount > 0 { Label("\(itemCount)", systemImage: "checklist") }
                Spacer()
                Text(note.date, format: .relative(presentation: .named))
            }
            .font(Theme.rounded(10, .medium))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(isSelected ? .regular.tint(Theme.accent.opacity(0.35)) : .regular, in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2)
                .fill(note.verdict.tint.opacity(0.85))
                .frame(height: 3)
                .padding(.horizontal, 14)
        }
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 4: Create LivePanelView**

Create `MyApp/Views/LivePanelView.swift`:

```swift
import SwiftUI
import SwiftData

/// The live-capture panel: the orb, the elapsed timer, transport controls,
/// and points streaming in as the live pass extracts them.
struct LivePanelView: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                orb
                status
                if coordinator.isActive || coordinator.state == .processing { transport }
                if !coordinator.livePoints.isEmpty { pointsList }
                if !coordinator.recentTranscript.isEmpty && coordinator.isActive { transcriptTicker }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Orb + status

    @ViewBuilder
    private var orb: some View {
        switch coordinator.state {
        case .idle:
            RecordOrb(isActive: false, size: 84) {
                Task { await coordinator.start(context: context) }
            }
            .padding(.top, 20)
        case .listening, .paused:
            ZStack {
                StateOrb(mode: .listening, size: 132)
                    .opacity(coordinator.state == .paused ? 0.35 : 1)
                    .saturation(coordinator.state == .paused ? 0.3 : 1)
                if coordinator.state == .paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.top, 12)
        case .processing:
            StateOrb(mode: .processing, size: 110)
                .padding(.top, 12)
        }
    }

    private var status: some View {
        VStack(spacing: 4) {
            switch coordinator.state {
            case .idle:
                Text("Ready to listen")
                    .font(Theme.rounded(13, .medium))
                    .foregroundStyle(.secondary)
            case .processing:
                Text("Summarizing your review…")
                    .font(Theme.rounded(13, .medium))
                    .foregroundStyle(.secondary)
            case .listening, .paused:
                Text(coordinator.elapsedText)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("\(coordinator.capturedPhraseCount) phrases\(coordinator.systemAudioActive ? " · you + participants" : "")")
                    .font(Theme.rounded(12, .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 16) {
            if coordinator.state == .listening {
                transportButton("pause.fill", help: "Pause") { await coordinator.pause() }
            } else if coordinator.state == .paused {
                transportButton("play.fill", help: "Resume") { await coordinator.resume() }
            }
            if coordinator.isActive {
                transportButton("stop.fill", help: "Stop & summarize") { await coordinator.stop() }
            }
        }
    }

    private func transportButton(_ icon: String, help: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Circle())
        .help(help)
    }

    // MARK: - Live points

    private var pointsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Points so far", systemImage: "sparkles")
                .font(Theme.rounded(11, .bold))
                .foregroundStyle(.secondary)
            ForEach(coordinator.livePoints, id: \.self) { point in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(.tertiary).frame(width: 4, height: 4).padding(.top, 6)
                    Text(point)
                        .font(Theme.rounded(13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Transcript ticker

    private var transcriptTicker: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(coordinator.recentTranscript.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(Theme.rounded(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(10)
            }
            .frame(height: 96)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .onChange(of: coordinator.recentTranscript.count) {
                withAnimation { proxy.scrollTo(coordinator.recentTranscript.count - 1, anchor: .bottom) }
            }
        }
    }
}
```

- [ ] **Step 5: Create RootShellView**

Create `MyApp/Views/Shell/RootShellView.swift`:

```swift
import SwiftUI
import SwiftData

/// The main window: three parallel glass panels (Library | Reader | Live) on
/// the dark backdrop, resizable and collapsible. The live panel auto-expands
/// when capture starts.
struct RootShellView: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @State private var layout = PanelLayoutModel()
    @State private var selection: ReviewNote?

    var body: some View {
        ZStack {
            PremiumBackground()
            PanelSplitView(model: layout) { panel in
                switch panel {
                case .library:
                    PanelChrome(title: "Library", systemImage: "books.vertical",
                                onCollapse: { layout.toggleCollapse(.library) },
                                accessory: {}) {
                        LibraryPane(selection: $selection)
                    }
                case .reader:
                    PanelChrome(title: "Review", systemImage: "doc.text",
                                onCollapse: { layout.toggleCollapse(.reader) },
                                accessory: {}) {
                        readerContent
                    }
                case .live:
                    PanelChrome(title: "Live", systemImage: "waveform",
                                onCollapse: { layout.toggleCollapse(.live) },
                                accessory: {}) {
                        LivePanelView()
                    }
                }
            }
            .padding(12)
        }
        .onChange(of: coordinator.state) { _, newValue in
            if newValue == .listening {
                withAnimation(.smooth) { layout.expandLive() }
            }
        }
    }

    @ViewBuilder
    private var readerContent: some View {
        if let selection {
            NoteDetailView(note: selection)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Select a review")
                    .font(Theme.display(20))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

- [ ] **Step 6: Point the window at the shell**

In `MyApp/RevueAIApp.swift`, replace the `WindowGroup` body (keep the id, tint, and color scheme):

```swift
        WindowGroup(id: "library") {
            RootShellView()
                .environment(coordinator)
                .frame(minWidth: 980, minHeight: 560)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        .defaultSize(width: 1240, height: 720)
```

Also remove the `.background { PremiumBackground() }` line from `MyApp/Views/NoteDetailView.swift:27` — the shell now owns the backdrop and the reader panel supplies glass.

- [ ] **Step 7: Build and run the full suite**

Run the Global Constraints test command.
Expected: `Test run with 50 tests in 8 suites passed`, `** TEST SUCCEEDED **`. Fix any compile errors in the new views before proceeding (the shell is UI-only; no test count changes).

- [ ] **Step 8: Launch the app and verify by hand**

```bash
DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer xcodebuild build -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' && open ~/Library/Developer/Xcode/DerivedData/RevueAI-*/Build/Products/Debug/RevueAI.app
```

Check: three glass panels appear; dividers drag; panels collapse to rails and re-expand; library selection drives the reader; the record dock still starts a capture and the live panel expands.

- [ ] **Step 9: Commit**

```bash
git add MyApp
git commit -m "feat: three-panel glass shell replaces the split-view window"
```

---

### Task 3: Item detail popup windows

Clicking an action item, question, or decision opens a separate glass window with the full detail.

**Files:**
- Create: `MyApp/Views/ItemPopup.swift`
- Create: `RevueAITests/ItemPopupRefTests.swift`
- Rewrite: `MyApp/Views/LayeredActionCard.swift` (`ActionRow` becomes compact; click opens popup)
- Modify: `MyApp/Views/ActionItemBoard.swift` (question rows open popup)
- Modify: `MyApp/Views/NoteDetailView.swift` (decision rows open popup)
- Modify: `MyApp/RevueAIApp.swift` (register the popup `WindowGroup`)

**Interfaces:**
- Consumes: `ActionItem`, `OpenQuestion`, `Decision` (all have `var id: UUID`), `PriorityBadge`, `CategoryChip`, `Theme`.
- Produces: `enum ItemPopupRef: Codable, Hashable` with cases `.actionItem(UUID)`, `.question(UUID)`, `.decision(UUID)`; `ItemPopupWindowView(ref: ItemPopupRef?)`. Windows open via `openWindow(value: ItemPopupRef...)`.

- [ ] **Step 1: Write the failing test**

Create `RevueAITests/ItemPopupRefTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct ItemPopupRefTests {
    @Test func roundTripsThroughCodable() throws {
        let id = UUID()
        let refs: [ItemPopupRef] = [.actionItem(id), .question(id), .decision(id)]
        for ref in refs {
            let data = try JSONEncoder().encode(ref)
            let decoded = try JSONDecoder().decode(ItemPopupRef.self, from: data)
            #expect(decoded == ref)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the Global Constraints test command.
Expected: build error — `cannot find 'ItemPopupRef' in scope`.

- [ ] **Step 3: Create the popup ref and window view**

Create `MyApp/Views/ItemPopup.swift`:

```swift
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
```

- [ ] **Step 4: Register the popup window scene**

In `MyApp/RevueAIApp.swift`, add after the main `WindowGroup` (before `MenuBarExtra`):

```swift
        WindowGroup(id: "itemPopup", for: ItemPopupRef.self) { $ref in
            ItemPopupWindowView(ref: ref)
                .environment(coordinator)
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 440, height: 480)
        .windowResizability(.contentMinSize)
```

- [ ] **Step 5: Rewrite ActionRow as a compact row that opens the popup**

Replace the entire contents of `MyApp/Views/LayeredActionCard.swift` with:

```swift
import SwiftUI

/// A compact action row for the dense board: priority dot + one-liner +
/// selection affordance. Clicking the row opens the item's detail in its own
/// glass popup window. Participates in the drag-to-complete board.
struct ActionRow: View {
    let item: ActionItem
    var isSelected = false
    var onToggleSelect: () -> Void = {}

    @Environment(\.openWindow) private var openWindow

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
        .onTapGesture { openWindow(value: ItemPopupRef.actionItem(item.id)) }
        .glassEffect(isSelected ? .regular.tint(Theme.accent.opacity(0.3)) : .regular, in: .rect(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 1.5)
        )
        .opacity(item.isDone ? 0.75 : 1)
        .help("Open details in a window")
    }
}
```

- [ ] **Step 6: Open popups from question and decision rows**

In `MyApp/Views/ActionItemBoard.swift`, replace the whole `private struct QuestionRow` (bottom of the file) with:

```swift
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
```

In `MyApp/Views/NoteDetailView.swift`, in `decisionsStrip`, add the environment to `NoteDetailView`:

```swift
    @Environment(\.openWindow) private var openWindow
```

and replace the decision row `HStack` inside `ForEach(decisions)` with:

```swift
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(decision.statement)
                    }
                    .font(Theme.rounded(13))
                    .foregroundStyle(.primary.opacity(0.9))
                    .contentShape(Rectangle())
                    .onTapGesture { openWindow(value: ItemPopupRef.decision(decision.id)) }
```

- [ ] **Step 7: Run the full suite**

Run the Global Constraints test command.
Expected: `Test run with 51 tests in 9 suites passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 8: Verify by hand**

Build and launch (same command as Task 2 Step 8). Open a note with action items; click a row → a borderless glass window opens with full detail; multiple windows can be open; marking complete in the popup updates the board.

- [ ] **Step 9: Commit**

```bash
git add MyApp RevueAITests/ItemPopupRefTests.swift
git commit -m "feat: glass popup windows for action items, questions, decisions"
```

---

### Task 4: OrbState machine + unified OrbView

One state-driven orb component used by the live panel and menu bar, mapping coordinator state (including a new `isExtracting` signal) to visual states.

**Spec deviation (deliberate):** the spec's "rim pulses with the live mic level" would require plumbing an audio-level signal out of the capture services, which the spec's own non-goals forbid (no pipeline changes). The listening state instead uses the existing animated `siriGlow` shader — continuously alive, just not level-reactive. Level-reactive pulsing can ride along with Spec B's capture-layer work if still wanted.

**Files:**
- Create: `MyApp/Views/OrbView.swift`
- Create: `RevueAITests/OrbStateTests.swift`
- Modify: `MyApp/CaptureCoordinator.swift:280-298` (additive `isExtracting` property)
- Modify: `MyApp/Views/LivePanelView.swift` (use `OrbView`)
- Modify: `MyApp/Views/CapturePanelView.swift:63-98,176-184` (use `OrbView`)

**Interfaces:**
- Consumes: `CaptureCoordinator.State`, existing `StateOrb` (shader orb) and `RecordOrb` visuals, `Theme`.
- Produces: `enum OrbState: Equatable { case idle, listening, paused, extracting, processing, error }` with `static func from(captureState: CaptureCoordinator.State, isExtracting: Bool, hasError: Bool) -> OrbState`; `OrbView(state: OrbState, size: CGFloat)`. `CaptureCoordinator` gains `private(set) var isExtracting: Bool`. Task 5's floating panel renders `OrbView`.

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/OrbStateTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct OrbStateTests {
    @Test func idleMapsToIdle() {
        #expect(OrbState.from(captureState: .idle, isExtracting: false, hasError: false) == .idle)
    }

    @Test func listeningMapsToListening() {
        #expect(OrbState.from(captureState: .listening, isExtracting: false, hasError: false) == .listening)
    }

    @Test func listeningWhileExtractingShimmers() {
        #expect(OrbState.from(captureState: .listening, isExtracting: true, hasError: false) == .extracting)
    }

    @Test func pausedMapsToPaused() {
        #expect(OrbState.from(captureState: .paused, isExtracting: false, hasError: false) == .paused)
    }

    @Test func processingMapsToProcessing() {
        #expect(OrbState.from(captureState: .processing, isExtracting: false, hasError: false) == .processing)
    }

    @Test func idleWithErrorShowsError() {
        #expect(OrbState.from(captureState: .idle, isExtracting: false, hasError: true) == .error)
    }

    @Test func activeCaptureOutranksError() {
        #expect(OrbState.from(captureState: .listening, isExtracting: false, hasError: true) == .listening)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the Global Constraints test command.
Expected: build error — `cannot find 'OrbState' in scope`.

- [ ] **Step 3: Implement OrbState + OrbView and the coordinator signal**

Create `MyApp/Views/OrbView.swift`:

```swift
import SwiftUI

/// The orb's visual state — a pure mapping from coordinator state so it can
/// be unit-tested and shared by every orb surface (live panel, menu bar,
/// floating window).
enum OrbState: Equatable {
    case idle
    case listening
    case paused
    case extracting
    case processing
    case error

    /// An error only shows on the orb once capture is fully stopped; during
    /// capture the orb keeps signalling that listening continues.
    static func from(captureState: CaptureCoordinator.State, isExtracting: Bool, hasError: Bool) -> OrbState {
        switch captureState {
        case .idle: return hasError ? .error : .idle
        case .paused: return .paused
        case .processing: return .processing
        case .listening: return isExtracting ? .extracting : .listening
        }
    }
}

/// The brand orb, rendered per state: shader glow while the AI is live,
/// static gradient when idle, dimmed when paused, grey on error. Respects
/// Reduce Motion by dropping the animated shader for a static gradient.
struct OrbView: View {
    let state: OrbState
    var size: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch state {
            case .idle:
                staticOrb(colors: [Theme.accent.opacity(0.9), Theme.accent.opacity(0.5)])
            case .listening:
                animatedOrDefault(mode: .listening)
            case .extracting:
                animatedOrDefault(mode: .listening)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.7), lineWidth: 2)
                            .blur(radius: 2)
                            .frame(width: size * 0.9, height: size * 0.9)
                    )
            case .paused:
                animatedOrDefault(mode: .listening)
                    .opacity(0.35)
                    .saturation(0.3)
                Image(systemName: "pause.fill")
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            case .processing:
                animatedOrDefault(mode: .processing)
            case .error:
                staticOrb(colors: [Color(white: 0.45), Color(white: 0.25)])
                Image(systemName: "exclamationmark")
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func animatedOrDefault(mode: StateOrb.Mode) -> some View {
        if reduceMotion {
            staticOrb(colors: mode == .processing
                      ? [Color(red: 0.36, green: 0.52, blue: 1.0), Theme.accent.opacity(0.6)]
                      : [Theme.accent, Color(red: 0.92, green: 0.42, blue: 0.78).opacity(0.7)])
        } else {
            StateOrb(mode: mode, size: size)
        }
    }

    private func staticOrb(colors: [Color]) -> some View {
        Circle()
            .fill(
                RadialGradient(colors: colors,
                               center: UnitPoint(x: 0.36, y: 0.30),
                               startRadius: 1,
                               endRadius: size * 0.62)
            )
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.04)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.5
                )
            )
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.3))
                    .blur(radius: size * 0.07)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .offset(x: size * 0.12, y: size * 0.1)
            }
            .frame(width: size * 0.86, height: size * 0.86)
    }

    private var accessibilityText: String {
        switch state {
        case .idle: "Idle"
        case .listening: "Listening"
        case .paused: "Paused"
        case .extracting: "Listening, extracting points"
        case .processing: "Summarizing"
        case .error: "Capture error"
        }
    }
}
```

In `MyApp/CaptureCoordinator.swift`, add below `private(set) var systemAudioActive = false` (line 29):

```swift
    /// True while a live-extraction call is in flight — drives the orb's
    /// extracting shimmer. Purely observational; no pipeline behavior changes.
    private(set) var isExtracting = false
```

And in `runLiveExtraction()`, wrap the extraction call. Replace:

```swift
        do {
            try await liveExtractor.extractAndCheckpoint(chunk: chunk, into: note, context: context)
```

with:

```swift
        isExtracting = true
        defer { isExtracting = false }
        do {
            try await liveExtractor.extractAndCheckpoint(chunk: chunk, into: note, context: context)
```

- [ ] **Step 4: Swap the orb into LivePanelView and CapturePanelView**

In `MyApp/Views/LivePanelView.swift`, replace the whole `orb` computed property with:

```swift
    @ViewBuilder
    private var orb: some View {
        if coordinator.state == .idle {
            RecordOrb(isActive: false, size: 84) {
                Task { await coordinator.start(context: context) }
            }
            .padding(.top, 20)
        } else {
            OrbView(state: OrbState.from(captureState: coordinator.state,
                                         isExtracting: coordinator.isExtracting,
                                         hasError: coordinator.errorMessage != nil),
                    size: 132)
                .padding(.top, 12)
        }
    }
```

In `MyApp/Views/CapturePanelView.swift`:
- In `captureView`, replace the `ZStack { Circle()...StateOrb...pause image }` block (the first child of the outer `VStack(spacing: 20)`) with:

```swift
            ZStack {
                Circle()
                    .fill(.white.opacity(0.04))
                    .frame(width: 168, height: 168)
                OrbView(state: OrbState.from(captureState: coordinator.state,
                                             isExtracting: coordinator.isExtracting,
                                             hasError: coordinator.errorMessage != nil),
                        size: 148)
            }
            .animation(.smooth, value: coordinator.state)
```

- In `processingView`, replace `StateOrb(mode: .processing, size: 110)` with:

```swift
            OrbView(state: .processing, size: 110)
```

- [ ] **Step 5: Run the full suite**

Run the Global Constraints test command.
Expected: `Test run with 58 tests in 10 suites passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MyApp RevueAITests/OrbStateTests.swift
git commit -m "feat: unified state-driven OrbView with extracting shimmer"
```

---

### Task 5: Floating orb window

An always-on-top, non-activating glass orb that appears during capture, draggable with a remembered position, click to open the app, right-click to stop.

**Files:**
- Create: `MyApp/Views/Shell/FloatingOrbController.swift`
- Create: `RevueAITests/FloatingOrbControllerTests.swift`
- Modify: `MyApp/Views/Shell/RootShellView.swift` (drive the controller)

**Interfaces:**
- Consumes: `OrbView`/`OrbState` (Task 4), `CaptureCoordinator`.
- Produces: `FloatingOrbController` (`@MainActor` class) with `static func shouldFloat(state: CaptureCoordinator.State, enabled: Bool) -> Bool` and `func update(state:enabled:coordinator:)`. Task 6's Settings toggles the `"floatingOrbEnabled"` AppStorage key this reads.

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/FloatingOrbControllerTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct FloatingOrbControllerTests {
    @Test func floatsWhileCaptureIsActive() {
        #expect(FloatingOrbController.shouldFloat(state: .listening, enabled: true))
        #expect(FloatingOrbController.shouldFloat(state: .paused, enabled: true))
        #expect(FloatingOrbController.shouldFloat(state: .processing, enabled: true))
    }

    @Test func neverFloatsWhenIdle() {
        #expect(!FloatingOrbController.shouldFloat(state: .idle, enabled: true))
    }

    @Test func neverFloatsWhenDisabled() {
        #expect(!FloatingOrbController.shouldFloat(state: .listening, enabled: false))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the Global Constraints test command.
Expected: build error — `cannot find 'FloatingOrbController' in scope`.

- [ ] **Step 3: Implement the controller**

Create `MyApp/Views/Shell/FloatingOrbController.swift`:

```swift
import AppKit
import SwiftUI

/// Owns the floating capture orb: a small always-on-top, non-activating
/// borderless panel visible over any app while a capture is running.
/// Click activates RevueAI; right-click offers Stop / Open. Draggable, with
/// its position remembered across sessions.
@MainActor
final class FloatingOrbController {
    private var panel: NSPanel?
    private static let originKey = "floatingOrb.origin"

    static func shouldFloat(state: CaptureCoordinator.State, enabled: Bool) -> Bool {
        enabled && state != .idle
    }

    func update(state: CaptureCoordinator.State, enabled: Bool, coordinator: CaptureCoordinator) {
        if Self.shouldFloat(state: state, enabled: enabled) {
            show(coordinator: coordinator)
        } else {
            hide()
        }
    }

    private func show(coordinator: CaptureCoordinator) {
        guard panel == nil else { return }
        let hosting = NSHostingView(rootView: FloatingOrbContent().environment(coordinator))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        if let stored = UserDefaults.standard.string(forKey: Self.originKey) {
            panel.setFrameOrigin(NSPointFromString(stored))
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 120,
                                         y: screen.visibleFrame.maxY - 120))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func hide() {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
        panel.orderOut(nil)
        self.panel = nil
    }
}

/// The floating panel's SwiftUI content: the orb, click-through to the app,
/// and a stop/open context menu.
private struct FloatingOrbContent: View {
    @Environment(CaptureCoordinator.self) private var coordinator

    var body: some View {
        OrbView(state: OrbState.from(captureState: coordinator.state,
                                     isExtracting: coordinator.isExtracting,
                                     hasError: coordinator.errorMessage != nil),
                size: 84)
            .padding(6)
            .contentShape(Circle())
            .onTapGesture { openMainWindow() }
            .contextMenu {
                Button("Stop & summarize") { Task { await coordinator.stop() } }
                Button("Open RevueAI") { openMainWindow() }
            }
            .help("RevueAI is listening — click to open")
    }

    private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows
            .first { $0.identifier?.rawValue.hasPrefix("library") == true }?
            .makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 4: Drive the controller from the shell**

In `MyApp/Views/Shell/RootShellView.swift`, add state and wiring. Add to the property block:

```swift
    @AppStorage("floatingOrbEnabled") private var floatingOrbEnabled = true
    @State private var floatingOrb = FloatingOrbController()
```

Add these modifiers after the existing `.onChange(of: coordinator.state)` block (extending, not replacing, it):

```swift
        .onChange(of: coordinator.state) { _, newValue in
            floatingOrb.update(state: newValue, enabled: floatingOrbEnabled, coordinator: coordinator)
        }
        .onChange(of: floatingOrbEnabled) { _, enabled in
            floatingOrb.update(state: coordinator.state, enabled: enabled, coordinator: coordinator)
        }
```

- [ ] **Step 5: Run the full suite**

Run the Global Constraints test command.
Expected: `Test run with 61 tests in 11 suites passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Verify by hand**

Build and launch. Start a capture, then switch to another app: the orb floats on top, draggable; right-click → Stop & summarize ends the session and the orb disappears; restart capture — the orb reappears where you left it.

- [ ] **Step 7: Commit**

```bash
git add MyApp RevueAITests/FloatingOrbControllerTests.swift
git commit -m "feat: floating always-on-top orb during capture"
```

---

### Task 6: TourKit onboarding + Settings

First-run onboarding: TourKit slideshow (brand + privacy story) followed by a guided permissions step, plus a Settings scene to re-run the tour and toggle the floating orb.

**Files:**
- Modify: `RevueAI.xcodeproj/project.pbxproj` (add the TourKit SPM package)
- Create: `MyApp/Onboarding/OnboardingPages.swift`
- Create: `MyApp/Onboarding/OnboardingSheet.swift`
- Create: `MyApp/Views/SettingsView.swift`
- Create: `RevueAITests/OnboardingPagesTests.swift`
- Modify: `MyApp/RevueAIApp.swift` (Settings scene)
- Modify: `MyApp/Views/Shell/RootShellView.swift` (present onboarding)

**Interfaces:**
- Consumes: TourKit (`https://github.com/rampatra/TourKit`, SwiftUI slideshow), `OrbView`, `AVCaptureDevice` (mic permission), `FloatingOrbController`'s `"floatingOrbEnabled"` key.
- Produces: `OnboardingPage` model + `OnboardingPage.all: [OnboardingPage]` (5 pages), `OnboardingSheet(isPresented:onStartCapture:)`, `SettingsView`, AppStorage key `"hasCompletedOnboarding"`.

- [ ] **Step 1: Add the TourKit package to the project**

In `RevueAI.xcodeproj/project.pbxproj`:

1. Add a new section before `/* Begin PBXContainerItemProxy section */`:

```
/* Begin PBXBuildFile section */
		AA0000000000000000000003 /* TourKit in Frameworks */ = {isa = PBXBuildFile; productRef = AA0000000000000000000002 /* TourKit */; };
/* End PBXBuildFile section */
```

2. In the app target's Frameworks phase (`000000000000000130000000 /* Frameworks */`), change `files = (` to include the build file:

```
			files = (
				AA0000000000000000000003 /* TourKit in Frameworks */,
			);
```

3. In the `PBXNativeTarget` for RevueAI (`000000000000000100000000`), add after `name = RevueAI;`:

```
			packageProductDependencies = (
				AA0000000000000000000002 /* TourKit */,
			);
```

4. In the `PBXProject` object (`000000000000000000000000`), add after `minimizedProjectReferenceProxies = 1;`:

```
			packageReferences = (
				AA0000000000000000000001 /* XCRemoteSwiftPackageReference "TourKit" */,
			);
```

5. Add two new sections before `/* End XCConfigurationList section */`'s closing (i.e. after the XCConfigurationList section, before the closing `};` of `objects`):

```
/* Begin XCRemoteSwiftPackageReference section */
		AA0000000000000000000001 /* XCRemoteSwiftPackageReference "TourKit" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/rampatra/TourKit";
			requirement = {
				branch = main;
				kind = branch;
			};
		};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		AA0000000000000000000002 /* TourKit */ = {
			isa = XCSwiftPackageProductDependency;
			package = AA0000000000000000000001 /* XCRemoteSwiftPackageReference "TourKit" */;
			productName = TourKit;
		};
/* End XCSwiftPackageProductDependency section */
```

Then resolve and verify:

```bash
DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer xcodebuild -resolvePackageDependencies -project RevueAI.xcodeproj -scheme RevueAI
```

Expected: `Resolved source packages: TourKit: https://github.com/rampatra/TourKit @ main`. If resolution fails on sandbox/network settings, note that `ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO` affects the app sandbox only, not package resolution; check the URL and retry.

**API check (required):** after resolution, read the package's public API before writing Step 4's view:

```bash
find ~/Library/Developer/Xcode/DerivedData/RevueAI-*/SourcePackages/checkouts/TourKit/Sources -name "*.swift" | xargs grep -l "public" | head; grep -rn "public struct\|public init\|public class" ~/Library/Developer/Xcode/DerivedData/RevueAI-*/SourcePackages/checkouts/TourKit/Sources | head -30
```

Step 4 below writes against the README's documented shape (`TourSlideshowView` with pages of image/title/description). If the actual initializer differs, adapt the call site in `OnboardingSheet.swift` — keep the page copy and flow identical.

- [ ] **Step 2: Write the failing test**

Create `RevueAITests/OnboardingPagesTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct OnboardingPagesTests {
    @Test func fiveCompletePages() {
        #expect(OnboardingPage.all.count == 5)
        for page in OnboardingPage.all {
            #expect(!page.title.isEmpty)
            #expect(!page.subtitle.isEmpty)
        }
    }

    @Test func tourCoversPermissionsAndCapture() {
        let titles = OnboardingPage.all.map(\.title).joined(separator: " ")
        #expect(titles.contains("Microphone"))
        #expect(titles.contains("Participants"))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run the Global Constraints test command.
Expected: build error — `cannot find 'OnboardingPage' in scope`.

- [ ] **Step 4: Implement pages, sheet, and Settings**

Create `MyApp/Onboarding/OnboardingPages.swift`:

```swift
import Foundation

/// Content for the first-run tour. Kept as plain data so the copy is testable
/// and the presentation layer (TourKit) stays swappable.
struct OnboardingPage: Identifiable {
    let id: Int
    let systemImage: String
    let title: String
    let subtitle: String

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            systemImage: "circle.hexagongrid.fill",
            title: "Meet RevueAI",
            subtitle: "Your reviews, captured as structured notes — summaries, action items, and decisions, extracted live while you talk."
        ),
        OnboardingPage(
            id: 1,
            systemImage: "lock.shield.fill",
            title: "Nothing is ever recorded",
            subtitle: "Audio is transcribed on-device and discarded instantly. No recordings, no transcripts on disk — only the structured note survives."
        ),
        OnboardingPage(
            id: 2,
            systemImage: "mic.fill",
            title: "Microphone access",
            subtitle: "RevueAI listens through your mic to transcribe what you say. You'll grant this on the next screen."
        ),
        OnboardingPage(
            id: 3,
            systemImage: "person.2.wave.2.fill",
            title: "Hear Participants too",
            subtitle: "To capture the other side of Zoom, Meet, or Teams calls, RevueAI needs System Audio Recording — enabled in Privacy & Security."
        ),
        OnboardingPage(
            id: 4,
            systemImage: "waveform",
            title: "Start your first capture",
            subtitle: "Hit the orb when your next review starts. Stop when it ends — your note is ready seconds later."
        ),
    ]
}
```

Create `MyApp/Onboarding/OnboardingSheet.swift`:

```swift
import SwiftUI
import AVFoundation
import TourKit

/// First-run flow: the TourKit slideshow (brand + privacy story), then a
/// guided permissions step, ending in "start your first capture". Skippable
/// at any point; re-runnable from Settings. Never blocks capture — closing
/// the sheet always leaves the app fully usable.
struct OnboardingSheet: View {
    @Binding var isPresented: Bool
    var onStartCapture: () -> Void

    private enum Phase { case tour, permissions }
    @State private var phase: Phase = .tour
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .tour: tourPhase
            case .permissions: permissionsPhase
            }
        }
        .frame(width: 520, height: 480)
        .background(Color(white: 0.07))
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    // MARK: - Tour

    private var tourPhase: some View {
        VStack(spacing: 12) {
            TourSlideshowView(
                pages: OnboardingPage.all.map { page in
                    TourPage(
                        image: Image(systemName: page.systemImage),
                        title: page.title,
                        description: page.subtitle
                    )
                }
            )
            .frame(maxHeight: .infinity)

            HStack {
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Set up permissions") {
                    withAnimation(.smooth) { phase = .permissions }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
    }

    // MARK: - Permissions

    private var permissionsPhase: some View {
        VStack(alignment: .leading, spacing: 18) {
            OrbView(state: .idle, size: 72)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

            Text("Two permissions, full privacy")
                .font(Theme.display(20))
                .frame(maxWidth: .infinity)

            permissionRow(
                icon: "mic.fill",
                title: "Microphone",
                detail: "Transcribes your side on-device.",
                done: micGranted
            ) {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in micGranted = granted }
                }
            }

            permissionRow(
                icon: "person.2.wave.2.fill",
                title: "System Audio Recording",
                detail: "Captures participants in online meetings. Opens Privacy & Security — enable RevueAI there.",
                done: false
            ) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }

            Spacer()

            HStack {
                Button("Done") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Start my first capture") {
                    finish()
                    onStartCapture()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    private func permissionRow(icon: String, title: String, detail: String, done: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.rounded(14, .semibold))
                Text(detail).font(Theme.rounded(11)).foregroundStyle(.secondary)
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.55))
            } else {
                Button("Enable", action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func finish() {
        isPresented = false
    }
}
```

Create `MyApp/Views/SettingsView.swift`:

```swift
import SwiftUI

/// App settings: floating orb, participants capture, and the welcome tour.
struct SettingsView: View {
    @AppStorage("floatingOrbEnabled") private var floatingOrbEnabled = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Show floating orb while listening", isOn: $floatingOrbEnabled)
            }
            Section("Help") {
                Button("Show Welcome Tour") {
                    hasCompletedOnboarding = false
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                Text("The tour reopens in the main window.")
                    .font(Theme.rounded(11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .preferredColorScheme(.dark)
    }
}
```

In `MyApp/RevueAIApp.swift`, add a Settings scene after the `MenuBarExtra`:

```swift
        Settings {
            SettingsView()
                .tint(Theme.accent)
        }
```

In `MyApp/Views/Shell/RootShellView.swift`, add the presentation. Add to the property block:

```swift
    @Environment(\.modelContext) private var context
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
```

Add these modifiers to the `ZStack` (alongside the existing `.onChange` handlers):

```swift
        .onAppear {
            if !hasCompletedOnboarding { showOnboarding = true }
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if !completed { showOnboarding = true }
        }
        .sheet(isPresented: $showOnboarding, onDismiss: { hasCompletedOnboarding = true }) {
            OnboardingSheet(isPresented: $showOnboarding) {
                Task { await coordinator.start(context: context) }
            }
        }
```

- [ ] **Step 5: Run the full suite**

Run the Global Constraints test command.
Expected: `Test run with 63 tests in 12 suites passed`, `** TEST SUCCEEDED **`. If `TourSlideshowView`/`TourPage` fail to compile, re-check the package API per Step 1's API check and adapt only the call site inside `tourPhase`.

- [ ] **Step 6: Verify by hand**

```bash
defaults delete com.thakurshourya.RevueAI hasCompletedOnboarding 2>/dev/null; true
```

Build and launch. The tour sheet appears with 5 slides; "Set up permissions" shows the two permission rows; mic Enable triggers the system prompt; system-audio Enable opens Privacy & Security; "Done" closes and never re-appears on relaunch; Settings → "Show Welcome Tour" brings it back.

- [ ] **Step 7: Commit**

```bash
git add RevueAI.xcodeproj/project.pbxproj MyApp RevueAITests/OnboardingPagesTests.swift
git commit -m "feat: TourKit onboarding flow and app Settings"
```

---

### Task 7: Orb app icon

Generate an orb-on-black macOS app icon with a script and wire it into an asset catalog.

**Files:**
- Create: `Tools/render-appicon.swift`
- Create: `MyApp/Assets.xcassets/Contents.json`
- Create: `MyApp/Assets.xcassets/AppIcon.appiconset/Contents.json` (+ generated PNGs)
- Modify: `RevueAI.xcodeproj/project.pbxproj` (both app-target configurations gain `ASSETCATALOG_COMPILER_APPICON_NAME`)

**Interfaces:**
- Consumes: nothing from the app (standalone AppKit script).
- Produces: `AppIcon` asset compiled into the app bundle.

- [ ] **Step 1: Write the icon renderer**

Create `Tools/render-appicon.swift`:

```swift
#!/usr/bin/swift
// Renders the RevueAI orb app icon: a glassy orb with a chromatic rim on
// near-black, at every size macOS needs. Usage:
//   swift Tools/render-appicon.swift MyApp/Assets.xcassets/AppIcon.appiconset
import AppKit

func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    let context = NSGraphicsContext.current!.cgContext

    // Background: near-black rounded square (system applies the final mask).
    let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.22
    let path = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    context.addPath(path)
    context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1))
    context.fillPath()

    // Orb body.
    let orbDiameter = size * 0.56
    let orbRect = CGRect(x: (size - orbDiameter) / 2, y: (size - orbDiameter) / 2,
                         width: orbDiameter, height: orbDiameter)
    let colors = [
        CGColor(red: 0.30, green: 0.28, blue: 0.36, alpha: 1),
        CGColor(red: 0.10, green: 0.09, blue: 0.13, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors, locations: [0, 1])!
    context.saveGState()
    context.addEllipse(in: orbRect)
    context.clip()
    context.drawRadialGradient(
        gradient,
        startCenter: CGPoint(x: orbRect.midX - orbDiameter * 0.14, y: orbRect.midY + orbDiameter * 0.2),
        startRadius: 1,
        endCenter: CGPoint(x: orbRect.midX, y: orbRect.midY),
        endRadius: orbDiameter * 0.62,
        options: .drawsAfterEndLocation
    )

    // Chromatic horizon band across the middle (the aurora sliver).
    let bandColors = [
        CGColor(red: 1.0, green: 0.85, blue: 0.6, alpha: 0.0),
        CGColor(red: 1.0, green: 0.9, blue: 0.75, alpha: 0.9),
        CGColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 0.6),
        CGColor(red: 0.9, green: 0.5, blue: 0.8, alpha: 0.0),
    ] as CFArray
    let band = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: bandColors, locations: [0.0, 0.45, 0.6, 1.0])!
    let bandRect = CGRect(x: orbRect.minX, y: orbRect.midY - orbDiameter * 0.06,
                          width: orbDiameter, height: orbDiameter * 0.12)
    context.saveGState()
    context.clip(to: bandRect)
    context.drawLinearGradient(band,
                               start: CGPoint(x: bandRect.minX, y: bandRect.midY),
                               end: CGPoint(x: bandRect.maxX, y: bandRect.midY),
                               options: [])
    context.restoreGState()

    // Top specular highlight.
    let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [CGColor(gray: 1, alpha: 0.5), CGColor(gray: 1, alpha: 0)] as CFArray,
                               locations: [0, 1])!
    context.drawRadialGradient(
        highlight,
        startCenter: CGPoint(x: orbRect.midX - orbDiameter * 0.12, y: orbRect.maxY - orbDiameter * 0.22),
        startRadius: 1,
        endCenter: CGPoint(x: orbRect.midX - orbDiameter * 0.12, y: orbRect.maxY - orbDiameter * 0.22),
        endRadius: orbDiameter * 0.35,
        options: []
    )
    context.restoreGState()

    // Thin rim.
    context.addEllipse(in: orbRect.insetBy(dx: 0.5, dy: 0.5))
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.25))
    context.setLineWidth(max(1, size * 0.004))
    context.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outputDirArg = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "MyApp/Assets.xcassets/AppIcon.appiconset"
let outputDir = URL(fileURLWithPath: outputDirArg)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for pixels in sizes {
    let rep = renderIcon(pixels: pixels)
    let url = outputDir.appendingPathComponent("icon_\(pixels).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}
```

- [ ] **Step 2: Create the asset catalog**

Create `MyApp/Assets.xcassets/Contents.json`:

```json
{
  "info" : { "author" : "xcode", "version" : 1 }
}
```

Create `MyApp/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images" : [
    { "filename" : "icon_16.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_64.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png",  "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 3: Render the icons**

```bash
cd /Users/shouryathakur/Development/Swift_Projects/RevueAI && DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer swift Tools/render-appicon.swift MyApp/Assets.xcassets/AppIcon.appiconset
```

Expected: seven `wrote .../icon_N.png` lines. Open `icon_1024.png` to eyeball it: dark orb, warm-to-blue horizon band, top highlight, on near-black.

- [ ] **Step 4: Wire the icon into the build**

In `RevueAI.xcodeproj/project.pbxproj`, in BOTH app-target configurations (`000000000000000111000000` Debug and `000000000000000112000000` Release), add this line inside `buildSettings` (before `CODE_SIGN_STYLE = Automatic;`, keeping the list alphabetical):

```
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
```

- [ ] **Step 5: Build and verify the icon**

```bash
DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer xcodebuild build -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD" && ls ~/Library/Developer/Xcode/DerivedData/RevueAI-*/Build/Products/Debug/RevueAI.app/Contents/Resources/ | grep -i appicon
```

Expected: `** BUILD SUCCEEDED **` and `AppIcon.icns` in Resources. Launch the app: the Dock shows the orb icon.

- [ ] **Step 6: Run the full suite one last time**

Run the Global Constraints test command.
Expected: `Test run with 63 tests in 12 suites passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Tools MyApp/Assets.xcassets RevueAI.xcodeproj/project.pbxproj
git commit -m "feat: orb app icon rendered by script"
```

---

## Final verification (after Task 7)

- [ ] Full suite: the Global Constraints test command → `** TEST SUCCEEDED **`, 63 tests in 12 suites.
- [ ] Build: `DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer xcodebuild build -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS'` → `** BUILD SUCCEEDED **`.
- [ ] Manual walkthrough (needs the user): fresh-launch onboarding → grant mic → start a capture from the tour → floating orb appears over other apps → live panel expands and streams points → stop → click an action item → glass popup opens → collapse/resize panels → relaunch and confirm layout persisted and onboarding stays dismissed.
