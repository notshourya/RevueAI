# Onboarding v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the TourKit onboarding with a custom glass welcome sheet (live SwiftUI slides) plus a two-act guided in-app tour with spotlight callouts.

**Architecture:** A `TourController` (`@Observable`) walks a linear list of `TourStop`s; a `TourOverlay` modifier at the shell root dims the window, cuts a spotlight over the current stop's target (SwiftUI anchor preferences, or AppKit toolbar rects for search/export), and renders a glass callout. The welcome sheet becomes a hand-rolled pager whose slides embed live component previews. TourKit, its PNG art, and the render tool are deleted.

**Tech Stack:** SwiftUI (macOS 27), AppKit interop (NSToolbar rect resolution), Swift Testing (`import Testing`), SwiftData (existing).

**Spec:** `docs/superpowers/specs/2026-07-08-onboarding-v2-design.md`

## Global Constraints

- Build/test with the system-selected Xcode 27 beta: plain `xcodebuild` (no DEVELOPER_DIR prefix).
- Full test command: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' 2>&1 | grep -E "error:|Test run|TEST (SUCCEEDED|FAILED)"` — never `-quiet`.
- Gate every commit: run tests to a log file, then `grep -q "TEST SUCCEEDED" $LOG && git add <specific files> && git commit …`. Never chain `git add` after a *display* grep.
- NEVER `pkill` the app — the user runs it under the Xcode debugger.
- NEVER `git add -A`. A parallel session owns uncommitted changes in: `MyApp/RevueAIApp.swift`, `MyApp/Shaders.metal`, `MyApp/Capture/AudioLevelMonitor.swift`, `MyApp/Views/OrbConfig.swift`, `MyApp/Views/OrbTuningView.swift`, `MyApp/Views/SiriOrbView.swift`, `test_script.swift`. Stage files by exact path only.
- Re-read any file immediately before editing it — the parallel session causes edit collisions.
- Design language: rounded font design, small-caps kerned headers (`size: 11, weight: .heavy/.bold, design: .rounded`, `kerning(0.8)`), `.glassEffect` surfaces, no brand color (system accent only).
- The Xcode project uses file-system-synchronized groups: new `.swift` files dropped into `MyApp/` or `RevueAITests/` are picked up automatically — no pbxproj edits needed to add files.

---

### Task 1: Tour model (stops, controller, scripts)

**Files:**
- Create: `MyApp/Onboarding/TourModel.swift`
- Test: `RevueAITests/TourModelTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `TourStop` (`id: String`, `title: String`, `body: String`, `anchorID: String?`, `arrowEdge: Edge`, `actionTitle: String?`); `TourController` (`@Observable @MainActor`: `current: TourStop?`, `index: Int`, `stops: [TourStop]`, `isActive: Bool`, `isLastStop: Bool`, `begin(_:onFinished:)`, `advance()`, `skip()`); `TourScript.act1`, `TourScript.act2`, `TourScript.shouldRunBoardTour(itemCount:hasSeenBoardTour:) -> Bool`. Anchor id strings: `"assistant-search"`, `"date-ruler"`, `"board-todo"`, `"action-item"`, `"export-menu"`.

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/TourModelTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct TourModelTests {
    @Test func actsAreWellFormed() {
        #expect(!TourScript.act1.isEmpty)
        #expect(!TourScript.act2.isEmpty)
        let ids = (TourScript.act1 + TourScript.act2).map(\.id)
        #expect(Set(ids).count == ids.count)
        for stop in TourScript.act1 + TourScript.act2 {
            #expect(!stop.title.isEmpty)
            #expect(!stop.body.isEmpty)
        }
    }

    @Test func act1EndsWithCenteredCaptureCard() {
        let last = TourScript.act1.last!
        #expect(last.anchorID == nil)
        #expect(last.actionTitle != nil)
    }

    @Test @MainActor func controllerWalksAndFinishes() {
        let controller = TourController()
        var finished = false
        let stops = [TourStop(id: "a", title: "A", body: "a"),
                     TourStop(id: "b", title: "B", body: "b")]
        controller.begin(stops) { finished = true }
        #expect(controller.current?.id == "a")
        controller.advance()
        #expect(controller.current?.id == "b")
        #expect(controller.isLastStop)
        controller.advance()
        #expect(finished)
        #expect(!controller.isActive)
        #expect(controller.current == nil)
    }

    @Test @MainActor func skipFinishesImmediately() {
        let controller = TourController()
        var finished = false
        controller.begin([TourStop(id: "a", title: "A", body: "a")]) { finished = true }
        controller.skip()
        #expect(finished)
        #expect(!controller.isActive)
    }

    @Test @MainActor func beginWithNoStopsIsIgnored() {
        let controller = TourController()
        var finished = false
        controller.begin([]) { finished = true }
        #expect(!controller.isActive)
        #expect(!finished)
    }

    @Test func boardTourTriggerPredicate() {
        #expect(TourScript.shouldRunBoardTour(itemCount: 3, hasSeenBoardTour: false))
        #expect(!TourScript.shouldRunBoardTour(itemCount: 0, hasSeenBoardTour: false))
        #expect(!TourScript.shouldRunBoardTour(itemCount: 3, hasSeenBoardTour: true))
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
LOG=/tmp/onb-t1.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' \
  -only-testing:RevueAITests/TourModelTests > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
```

Expected: build errors — `cannot find 'TourScript' in scope`, `cannot find 'TourController' in scope`.

- [ ] **Step 3: Implement the model**

Create `MyApp/Onboarding/TourModel.swift`:

```swift
import Foundation
import SwiftUI

/// One step of a guided tour. `anchorID` names a target registered via
/// `.tourAnchor(_:)` — or one of the AppKit toolbar ids TourOverlay
/// resolves itself ("assistant-search", "export-menu"). nil renders the
/// stop as a centered card.
struct TourStop: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    var anchorID: String? = nil
    var arrowEdge: Edge = .bottom
    /// Optional prominent action on the stop (e.g. "Start a capture").
    var actionTitle: String? = nil
}

/// Drives one act of the tour: a linear walk over its stops.
/// Skipping counts as seen — it fires the same completion as finishing.
@Observable @MainActor
final class TourController {
    private(set) var stops: [TourStop] = []
    private(set) var index = 0
    private(set) var isActive = false
    private var onFinished: (() -> Void)?

    var current: TourStop? {
        guard isActive, stops.indices.contains(index) else { return nil }
        return stops[index]
    }

    var isLastStop: Bool { index >= stops.count - 1 }

    func begin(_ stops: [TourStop], onFinished: @escaping () -> Void) {
        guard !stops.isEmpty else { return }
        self.stops = stops
        self.onFinished = onFinished
        index = 0
        isActive = true
    }

    func advance() {
        guard isActive else { return }
        if isLastStop { finish() } else { index += 1 }
    }

    func skip() { finish() }

    private func finish() {
        guard isActive else { return }
        isActive = false
        stops = []
        index = 0
        onFinished?()
        onFinished = nil
    }
}

/// The two acts of the guided tour.
enum TourScript {
    static let act1: [TourStop] = [
        TourStop(id: "search",
                 title: "Ask across every review",
                 body: "Type a question here — the assistant answers from your notes and cites the reviews it used.",
                 anchorID: "assistant-search"),
        TourStop(id: "ruler",
                 title: "Your meetings, on a ruler",
                 body: "Scrub through your history like a timer dial. Settle on a past day to filter the library; click the date to see that day's agenda and arm meetings.",
                 anchorID: "date-ruler",
                 arrowEdge: .top),
        TourStop(id: "capture",
                 title: "Capture lives in your menu bar",
                 body: "Hit the orb in the menu bar when a review starts. Stop when it ends — the structured note is ready seconds later.",
                 actionTitle: "Start a capture"),
    ]

    static let act2: [TourStop] = [
        TourStop(id: "board",
                 title: "Work the board",
                 body: "Action items live in columns. Drag rows between To Do and Completed, or select several and complete them together.",
                 anchorID: "board-todo",
                 arrowEdge: .trailing),
        TourStop(id: "item",
                 title: "Every item opens up",
                 body: "Click a row for the full story — priority, tags, quotes. Your edits survive the AI's final polish.",
                 anchorID: "action-item",
                 arrowEdge: .bottom),
        TourStop(id: "export",
                 title: "Take the note with you",
                 body: "Copy the finished note as Markdown or share it from here.",
                 anchorID: "export-menu",
                 arrowEdge: .bottom),
    ]

    /// Act 2 fires only for a real note with extracted action items.
    static func shouldRunBoardTour(itemCount: Int, hasSeenBoardTour: Bool) -> Bool {
        itemCount > 0 && !hasSeenBoardTour
    }
}
```

- [ ] **Step 4: Run to verify pass**

Same command as Step 2. Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add MyApp/Onboarding/TourModel.swift RevueAITests/TourModelTests.swift
git commit -m "feat: tour model — stops, controller, two-act script"
```

---

### Task 2: Tour overlay (anchors, spotlight, AppKit rects)

**Files:**
- Create: `MyApp/Onboarding/TourOverlay.swift`

**Interfaces:**
- Consumes: `TourStop`, `TourController` from Task 1.
- Produces: `View.tourAnchor(_ id: String?)` (nil = no-op), `View.tourOverlay(controller:onAction:)` where `onAction: (String) -> Void` receives the stop id whose `actionTitle` button was clicked.

View-layer code: no unit tests; the gate is a clean build plus the existing suite. Spotlight geometry is verified manually in Task 6.

- [ ] **Step 1: Implement the overlay**

Create `MyApp/Onboarding/TourOverlay.swift`:

```swift
import SwiftUI
import AppKit

// MARK: - Anchor plumbing

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Registers this view as a tour target under `id`. nil is a no-op so
    /// callers can register conditionally (e.g. only the first row).
    func tourAnchor(_ id: String?) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { anchor in
            guard let id else { return [:] }
            return [id: anchor]
        }
    }

    /// Attaches the guided-tour overlay; call once, on the shell root.
    func tourOverlay(controller: TourController,
                     onAction: @escaping (String) -> Void = { _ in }) -> some View {
        modifier(TourOverlayModifier(controller: controller, onAction: onAction))
    }

    fileprivate func reverseMask<M: View>(@ViewBuilder _ mask: () -> M) -> some View {
        self.mask {
            Rectangle()
                .overlay(mask().blendMode(.destinationOut))
                .compositingGroup()
        }
    }
}

private extension NSView {
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let nested = subview.firstSubview(of: type) { return nested }
        }
        return nil
    }
}

// MARK: - Overlay modifier

struct TourOverlayModifier: ViewModifier {
    let controller: TourController
    var onAction: (String) -> Void

    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(TourAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if let stop = controller.current {
                        TourSpotlight(stop: stop,
                                      rect: rect(for: stop, anchors: anchors, proxy: proxy),
                                      size: proxy.size,
                                      controller: controller,
                                      onAction: onAction)
                    }
                }
                .ignoresSafeArea()
                .background(WindowProbe(window: $window))
            }
    }

    /// SwiftUI anchors win; the two toolbar ids fall back to AppKit lookup.
    /// nil (never registered / not found) renders a centered card instead.
    private func rect(for stop: TourStop,
                      anchors: [String: Anchor<CGRect>],
                      proxy: GeometryProxy) -> CGRect? {
        guard let id = stop.anchorID else { return nil }
        if let anchor = anchors[id] { return proxy[anchor] }
        switch id {
        case "assistant-search":
            return toolbarRect(proxy: proxy, last: false) { isSearchItem($0) }
        case "export-menu":
            // After ToolbarSearchCenterer's reorder the export menu is the
            // trailing-most real item, so match from the end.
            let spaces: Set<NSToolbarItem.Identifier> = [.flexibleSpace, .space]
            return toolbarRect(proxy: proxy, last: true) { item in
                !(item is NSTrackingSeparatorToolbarItem)
                    && !spaces.contains(item.itemIdentifier)
                    && !isSearchItem(item)
            }
        default:
            return nil
        }
    }

    private func isSearchItem(_ item: NSToolbarItem) -> Bool {
        item is NSSearchToolbarItem || item.view?.firstSubview(of: NSSearchField.self) != nil
    }

    /// Converts a toolbar item's AppKit frame into the overlay's top-left
    /// coordinate space. Returns nil when anything is missing — the stop
    /// then renders as a centered card (spec's fallback).
    private func toolbarRect(proxy: GeometryProxy, last: Bool,
                             matching: (NSToolbarItem) -> Bool) -> CGRect? {
        guard let window,
              let toolbar = window.toolbar,
              let contentView = window.contentView else { return nil }
        let items = toolbar.items
        guard let item = last ? items.last(where: matching) : items.first(where: matching),
              let view = item.view, view.window === window else { return nil }
        let inWindow = view.convert(view.bounds, to: nil)
        let flipped = CGRect(x: inWindow.minX,
                             y: contentView.frame.height - inWindow.maxY,
                             width: inWindow.width,
                             height: inWindow.height)
        let global = proxy.frame(in: .global)
        return flipped.offsetBy(dx: -global.minX, dy: -global.minY)
    }
}

/// Zero-size probe capturing the hosting NSWindow.
private struct WindowProbe: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in window = view?.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if window !== view.window {
            DispatchQueue.main.async { [weak view] in window = view?.window }
        }
    }
}

// MARK: - Spotlight + callout

private struct TourSpotlight: View {
    let stop: TourStop
    let rect: CGRect?
    let size: CGSize
    let controller: TourController
    var onAction: (String) -> Void

    private static let calloutWidth: CGFloat = 300
    private static let calloutEstimatedHeight: CGFloat = 150

    var body: some View {
        ZStack {
            backdrop
            callout
                .position(calloutPosition)
        }
        .transition(.opacity)
        .animation(.smooth(duration: 0.3), value: stop.id)
    }

    private var backdrop: some View {
        Color.black.opacity(0.42)
            .reverseMask {
                if let rect {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .frame(width: rect.width + 18, height: rect.height + 18)
                        .position(x: rect.midX, y: rect.midY)
                        .blur(radius: 2.5)
                }
            }
            // Swallow clicks so the tour is modal until Next/Skip.
            .contentShape(Rectangle())
            .onTapGesture {}
    }

    private var callout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STEP \(controller.index + 1) OF \(controller.stops.count)")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Text(stop.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(stop.body)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Skip tour") {
                    withAnimation(.smooth) { controller.skip() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.tertiary)
                .keyboardShortcut(.cancelAction)

                Spacer()

                if let actionTitle = stop.actionTitle {
                    Button(actionTitle) {
                        let id = stop.id
                        withAnimation(.smooth) { controller.advance() }
                        onAction(id)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(controller.isLastStop ? "Done" : "Next") {
                    withAnimation(.smooth) { controller.advance() }
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: Self.calloutWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    /// Places the callout beside the target on the stop's `arrowEdge` side,
    /// clamped to the window; centered when there is no target rect.
    private var calloutPosition: CGPoint {
        guard let rect else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let halfW = Self.calloutWidth / 2
        let halfH = Self.calloutEstimatedHeight / 2
        var point: CGPoint
        switch stop.arrowEdge {
        case .top:
            point = CGPoint(x: rect.midX, y: rect.minY - halfH - 22)
        case .bottom:
            point = CGPoint(x: rect.midX, y: rect.maxY + halfH + 22)
        case .leading:
            point = CGPoint(x: rect.minX - halfW - 22, y: rect.midY)
        case .trailing:
            point = CGPoint(x: rect.maxX + halfW + 22, y: rect.midY)
        }
        point.x = min(max(point.x, halfW + 16), size.width - halfW - 16)
        point.y = min(max(point.y, halfH + 16), size.height - halfH - 16)
        return point
    }
}
```

- [ ] **Step 2: Build and run the full suite**

```bash
LOG=/tmp/onb-t2.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
```

Expected: `TEST SUCCEEDED` (no behavior change yet — nothing calls the overlay).

- [ ] **Step 3: Commit**

```bash
grep -q "TEST SUCCEEDED" /tmp/onb-t2.log \
  && git add MyApp/Onboarding/TourOverlay.swift \
  && git commit -m "feat: tour overlay — spotlight backdrop, glass callout, AppKit toolbar rects"
```

---

### Task 3: Rewrite the welcome sheet (live slides, no TourKit)

**Files:**
- Modify: `MyApp/Onboarding/OnboardingPages.swift` (full rewrite)
- Modify: `MyApp/Onboarding/OnboardingSheet.swift` (full rewrite)
- Create: `MyApp/Onboarding/SlideArtView.swift`
- Test: `RevueAITests/OnboardingPagesTests.swift` (update)

**Interfaces:**
- Consumes: `OrbView(state:size:)`, `Theme`, `PremiumBackground` (existing).
- Produces: `SlideArt` enum (`orb, privacy, liveNote, ruler, assistant`), `OnboardingPage` (`id: Int`, `art: SlideArt`, `title: String`, `subtitle: String`, `static all: [OnboardingPage]`), `SlideArtView(art:)`. `OnboardingSheet(isPresented:onStartCapture:)` keeps its exact existing signature so RootShellView compiles unchanged.

Design note: the ruler slide is a *static visual mock* of the date ruler, not a live `DateRulerView` — embedding the real one would construct `CalendarPaneModel`/`CalendarService` (EventKit) before the permissions step. Documented deviation from the spec's "live mini DateRulerView"; visually faithful, side-effect free.

- [ ] **Step 1: Update the pages test (it must fail first)**

Replace the body of `RevueAITests/OnboardingPagesTests.swift` with:

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

    @Test func pageIDsAndArtAreUnique() {
        #expect(Set(OnboardingPage.all.map(\.id)).count == OnboardingPage.all.count)
        #expect(Set(OnboardingPage.all.map(\.art)).count == OnboardingPage.all.count)
    }

    @Test func slidesCoverPrivacyBoardRulerAssistant() {
        let text = OnboardingPage.all.map { $0.title + " " + $0.subtitle }
            .joined(separator: " ")
            .lowercased()
        #expect(text.contains("recorded"))
        #expect(text.contains("board"))
        #expect(text.contains("ruler"))
        #expect(text.contains("cites"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
LOG=/tmp/onb-t3a.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' \
  -only-testing:RevueAITests/OnboardingPagesTests > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
```

Expected: build error — `OnboardingPage` has no member `art`.

- [ ] **Step 3: Rewrite the page data**

Replace `MyApp/Onboarding/OnboardingPages.swift` entirely with:

```swift
import Foundation

/// Which live illustration a slide renders (see SlideArtView). Live views
/// instead of pre-rendered art: always in sync with the design, adaptive
/// to light/dark.
enum SlideArt: String, CaseIterable {
    case orb, privacy, liveNote, ruler, assistant
}

/// Content for the first-run tour. Plain data so the copy is testable.
struct OnboardingPage: Identifiable, Equatable {
    let id: Int
    let art: SlideArt
    let title: String
    let subtitle: String

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: 0, art: .orb,
            title: "Meet RevueAI",
            subtitle: "Your reviews, captured as structured notes — summaries, action items, and decisions, extracted live while you talk."
        ),
        OnboardingPage(
            id: 1, art: .privacy,
            title: "Nothing is ever recorded",
            subtitle: "Audio is transcribed on-device and discarded instantly. No recordings, no transcripts on disk — only the structured note survives."
        ),
        OnboardingPage(
            id: 2, art: .liveNote,
            title: "Talk, and the note builds itself",
            subtitle: "Action items land on a board you can curate — complete, reorder, tag. Your edits always survive the AI's final polish."
        ),
        OnboardingPage(
            id: 3, art: .ruler,
            title: "Your meetings, on a ruler",
            subtitle: "Scrub your history like a timer dial, filter the library by day, and arm upcoming meetings to capture themselves."
        ),
        OnboardingPage(
            id: 4, art: .assistant,
            title: "Ask your notes anything",
            subtitle: "The search bar is an assistant: it answers from your reviews and cites the notes it used."
        ),
    ]
}
```

- [ ] **Step 4: Create the live slide art**

Create `MyApp/Onboarding/SlideArtView.swift`:

```swift
import SwiftUI

/// Live illustrations for the welcome slides — real components and the
/// app's own glass, not PNGs. The ruler is a static mock: constructing the
/// real DateRulerView would touch EventKit before permissions are granted.
struct SlideArtView: View {
    let art: SlideArt
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch art {
        case .orb: OrbView(state: .idle, size: 130)
        case .privacy: privacy
        case .liveNote: liveNote
        case .ruler: ruler
        case .assistant: assistant
        }
    }

    private var privacy: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(Theme.success)
                .frame(width: 108, height: 108)
                .glassEffect(.regular, in: Circle())
            HStack(spacing: 8) {
                artChip("No recordings", systemImage: "waveform.slash")
                artChip("On-device", systemImage: "cpu")
            }
        }
    }

    private var liveNote: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                artChip("3 open", systemImage: "circle.dashed")
                artChip("1 done", systemImage: "checkmark.circle.fill", tint: Theme.success)
                artChip("2 questions", systemImage: "questionmark.circle", tint: Theme.warning)
            }
            fakeRow("Refine the canvas styling", tint: Theme.warning)
            fakeRow("Ship the API draft for review", tint: Theme.danger)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func fakeRow(_ text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12.5, weight: .medium, design: .rounded))
        }
    }

    private var ruler: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                Text(Date.now, format: .dateTime.day())
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)
            }
            HStack(spacing: 10) {
                ForEach(0..<13, id: \.self) { index in
                    Rectangle()
                        .fill(index == 6 ? Color.red : Color.secondary.opacity(0.5))
                        .frame(width: 2, height: index % 3 == 0 ? 28 : 17)
                }
            }
        }
        .padding(22)
        .glassEffect(.clear.tint(colorScheme == .dark ? .black.opacity(0.35) : .black.opacity(0.16)),
                     in: .rect(cornerRadius: 24))
    }

    private var assistant: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            Text("Which action items are still open?")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .frame(width: 340)
    }

    private func artChip(_ text: String, systemImage: String, tint: Color = .secondary) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
    }
}
```

- [ ] **Step 5: Rewrite the sheet**

Re-read `MyApp/Onboarding/OnboardingSheet.swift` first (collision-prone), then replace it entirely with:

```swift
import SwiftUI
import AVFoundation

/// First-run flow: a paged glass slideshow of live slides, then a guided
/// permissions step, ending in "start your first capture". Skippable at
/// any point; re-runnable from Settings. Never blocks capture — closing
/// the sheet always leaves the app fully usable.
struct OnboardingSheet: View {
    @Binding var isPresented: Bool
    var onStartCapture: () -> Void

    private enum Phase { case tour, permissions }
    @State private var phase: Phase = .tour
    @State private var pageIndex = 0
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    private var page: OnboardingPage { OnboardingPage.all[pageIndex] }
    private var isLastPage: Bool { pageIndex == OnboardingPage.all.count - 1 }

    var body: some View {
        Group {
            switch phase {
            case .tour: tourPhase
            case .permissions: permissionsPhase
            }
        }
        .frame(width: 560, height: 540)
        .background { PremiumBackground() }
    }

    // MARK: - Slides

    private var tourPhase: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding([.top, .horizontal], 16)

            Spacer()

            SlideArtView(art: page.art)
                .frame(height: 210)
                .id(page.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))

            VStack(spacing: 8) {
                Text(page.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(page.subtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 400)
            }
            .padding(.top, 18)
            .animation(.smooth, value: pageIndex)

            Spacer()

            dots.padding(.bottom, 16)

            HStack {
                if pageIndex > 0 {
                    Button("Back") { withAnimation(.smooth) { pageIndex -= 1 } }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isLastPage ? "Set up permissions" : "Continue") {
                    withAnimation(.smooth) {
                        if isLastPage { phase = .permissions } else { pageIndex += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingPage.all) { candidate in
                Circle()
                    .fill(candidate.id == pageIndex ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                    .frame(width: 7, height: 7)
                    .onTapGesture { withAnimation(.smooth) { pageIndex = candidate.id } }
            }
        }
    }

    // MARK: - Permissions

    private var permissionsPhase: some View {
        VStack(alignment: .leading, spacing: 18) {
            OrbView(state: .idle, size: 72)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

            Text("Two permissions, full privacy")
                .font(.system(size: 20, weight: .bold, design: .rounded))
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

    private func permissionRow(icon: String, title: String, detail: String,
                               done: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(detail).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
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

- [ ] **Step 6: Run to verify pass**

```bash
LOG=/tmp/onb-t3b.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
```

Expected: `TEST SUCCEEDED` (full suite — the sheet no longer imports TourKit but the package is still linked, which is fine).

- [ ] **Step 7: Commit**

```bash
grep -q "TEST SUCCEEDED" /tmp/onb-t3b.log \
  && git add MyApp/Onboarding/OnboardingPages.swift MyApp/Onboarding/OnboardingSheet.swift \
             MyApp/Onboarding/SlideArtView.swift RevueAITests/OnboardingPagesTests.swift \
  && git commit -m "feat: welcome sheet v2 — custom glass pager with live slides"
```

---

### Task 4: Remove TourKit, PNG art, and the render tool

**Files:**
- Modify: `RevueAI.xcodeproj/project.pbxproj` (remove 4 lines + 2 sections)
- Delete: `MyApp/Resources/TourArt/` (5 PNGs), `Tools/render-tour-art.swift`
- Delete if TourKit is its only entry: `RevueAI.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

**Interfaces:**
- Consumes: Task 3 (nothing imports TourKit anymore).
- Produces: a dependency-free project.

- [ ] **Step 1: Verify nothing references TourKit in source**

```bash
grep -rn "TourKit" MyApp Tools RevueAITests --include="*.swift"
```

Expected: only `Tools/render-tour-art.swift` (a comment), which is being deleted. If any `import TourKit` remains, stop — Task 3 is incomplete.

- [ ] **Step 2: Edit project.pbxproj**

Re-read the file around each match of `grep -n "TourKit" RevueAI.xcodeproj/project.pbxproj`. Remove, by exact content:

1. The `PBXBuildFile` line: `AA0000000000000000000003 /* TourKit in Frameworks */ = {isa = PBXBuildFile; productRef = AA0000000000000000000002 /* TourKit */; };`
2. The Frameworks build-phase entry line: `AA0000000000000000000003 /* TourKit in Frameworks */,`
3. The `packageProductDependencies` entry line: `AA0000000000000000000002 /* TourKit */,`
4. The `packageReferences` entry line: `AA0000000000000000000001 /* XCRemoteSwiftPackageReference "TourKit" */,`
5. The whole `XCRemoteSwiftPackageReference` section block (starts `AA0000000000000000000001 /* XCRemoteSwiftPackageReference "TourKit" */ = {`, ends `};`).
6. The whole `XCSwiftPackageProductDependency` section block (starts `AA0000000000000000000002 /* TourKit */ = {`, ends `};`).

If removing those blocks empties the `PBXFrameworksBuildPhase` `files = (...)` list or the `packageReferences = (...)` list, leave the now-empty list in place — empty lists are valid pbxproj.

- [ ] **Step 3: Delete the art and tool; prune Package.resolved**

```bash
git rm -r MyApp/Resources/TourArt
git rm Tools/render-tour-art.swift
# If TourKit was the only package, the resolved file is now meaningless:
grep -c '"identity"' RevueAI.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
# If the count is 1 (TourKit only):
git rm RevueAI.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
# If >1, edit the file and remove only the TourKit pin object instead.
```

- [ ] **Step 4: Full suite**

```bash
LOG=/tmp/onb-t4.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
```

Expected: `TEST SUCCEEDED`. If the build fails on pbxproj parsing, re-check Step 2 — a dangling comma or unbalanced brace is the usual culprit.

- [ ] **Step 5: Commit**

```bash
grep -q "TEST SUCCEEDED" /tmp/onb-t4.log \
  && git add RevueAI.xcodeproj/project.pbxproj \
  && git commit -m "chore: drop TourKit package, pre-rendered tour art, and render tool"
```

(`git rm` already staged the deletions.)

---

### Task 5: Shell integration — flags, triggers, anchors, Settings

**Files:**
- Modify: `MyApp/Views/Shell/RootShellView.swift` (state block ~lines 29–36, `.onAppear`/`.onChange`/`.sheet` block ~lines 88–98, add overlay + helper)
- Modify: `MyApp/Views/LibraryView.swift` (the `DateRulerView(...)` call in the bottom dock)
- Modify: `MyApp/Views/ActionItemBoard.swift` (To Do column + first action row anchors)
- Modify: `MyApp/Views/SettingsView.swift` (reset all three flags)

**Interfaces:**
- Consumes: `TourController`, `TourScript`, `.tourAnchor(_:)`, `.tourOverlay(controller:onAction:)` from Tasks 1–2.
- Produces: `@AppStorage` keys `"hasSeenMainTour"`, `"hasSeenBoardTour"` (read nowhere else).

Re-read every file in this task immediately before editing — all four are collision-prone with the parallel session.

- [ ] **Step 1: RootShellView — state**

Below the existing `@AppStorage("hasCompletedOnboarding")` line (~line 29), add:

```swift
    @AppStorage("hasSeenMainTour") private var hasSeenMainTour = false
    @AppStorage("hasSeenBoardTour") private var hasSeenBoardTour = false
    @State private var tour = TourController()
```

- [ ] **Step 2: RootShellView — Act 1 start + Act 2 trigger**

Replace the existing onboarding block:

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

with:

```swift
        .onAppear {
            if !hasCompletedOnboarding {
                showOnboarding = true
            } else {
                startMainTourIfNeeded()
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if !completed { showOnboarding = true }
        }
        .sheet(isPresented: $showOnboarding, onDismiss: {
            hasCompletedOnboarding = true
            startMainTourIfNeeded()
        }) {
            OnboardingSheet(isPresented: $showOnboarding) {
                Task { await coordinator.start(context: context) }
            }
        }
        .onChange(of: selection) { _, note in
            guard let note, !tour.isActive,
                  TourScript.shouldRunBoardTour(itemCount: note.actionItems?.count ?? 0,
                                                hasSeenBoardTour: hasSeenBoardTour) else { return }
            let noteID = note.id
            // Give the reader a beat to lay out before spotlighting it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard selection?.id == noteID, !tour.isActive else { return }
                withAnimation(.smooth) {
                    tour.begin(TourScript.act2) { hasSeenBoardTour = true }
                }
            }
        }
```

- [ ] **Step 3: RootShellView — overlay + helper**

Directly after `.overlay(alignment: .bottom) { promptCard }`, add:

```swift
        .tourOverlay(controller: tour) { stopID in
            if stopID == "capture" {
                Task { await coordinator.start(context: context) }
            }
        }
```

And add this private method next to `startFromPlanned`:

```swift
    private func startMainTourIfNeeded() {
        guard !hasSeenMainTour, !tour.isActive else { return }
        withAnimation(.smooth) {
            tour.begin(TourScript.act1) { hasSeenMainTour = true }
        }
    }
```

- [ ] **Step 4: LibraryView — date ruler anchor**

Find the call site: `grep -n "DateRulerView(" MyApp/Views/LibraryView.swift`. On the `DateRulerView(...)` expression in the bottom dock, append `.tourAnchor("date-ruler")` as the first modifier after its closing parenthesis.

- [ ] **Step 5: ActionItemBoard — board anchors**

In `ReviewBoard.body`, the first `actionColumn("To Do", ...)` call gets `.tourAnchor("board-todo")` appended.

In `actionColumn`, the `ActionRow(...)` inside the `ForEach` gets a conditional anchor: append to the existing `ActionRow(...).draggable(...)` chain:

```swift
                    .tourAnchor(item.id == items.first?.id ? "action-item" : nil)
```

(the `String?` overload from Task 2 makes nil a no-op).

- [ ] **Step 6: SettingsView — reset all flags**

Add below the existing `@AppStorage("hasCompletedOnboarding")` property:

```swift
    @AppStorage("hasSeenMainTour") private var hasSeenMainTour = false
    @AppStorage("hasSeenBoardTour") private var hasSeenBoardTour = false
```

and extend the button action:

```swift
                Button("Show Welcome Tour") {
                    hasCompletedOnboarding = false
                    hasSeenMainTour = false
                    hasSeenBoardTour = false
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
```

- [ ] **Step 7: Full suite**

```bash
LOG=/tmp/onb-t5.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
grep -q "TEST SUCCEEDED" /tmp/onb-t5.log \
  && git add MyApp/Views/Shell/RootShellView.swift MyApp/Views/LibraryView.swift \
             MyApp/Views/ActionItemBoard.swift MyApp/Views/SettingsView.swift \
  && git commit -m "feat: wire the two-act guided tour into the shell"
```

---

### Task 6: Verification pass

**Files:** none (manual + full suite).

- [ ] **Step 1: Full suite one more time** (same command/gating as Task 5 Step 7).

- [ ] **Step 2: Manual checklist (user runs via ⌘R)**

Ask the user to verify — Settings → "Show Welcome Tour" resets everything:

1. Sheet: five slides page smoothly, art adapts to light/dark, Skip works, permissions phase intact.
2. Sheet close → Act 1: spotlight on the search field (real toolbar rect), then the date ruler, then the centered menu-bar card; "Start a capture" works; Esc skips.
3. Open an existing note with action items → Act 2 fires once: To Do column, first row, export menu.
4. Replay from Settings runs the whole flow again.
5. Collapsed sidebar during Act 1: ruler stop falls back to a centered card (anchor unregistered) rather than pointing at nothing.

- [ ] **Step 3: Push**

```bash
git push origin main
```
