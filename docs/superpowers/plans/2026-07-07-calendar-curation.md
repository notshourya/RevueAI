# Calendar + Action-Item Curation Implementation Plan (Spec B)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** User curation of AI-extracted action items (tags, edits, manual items — all surviving the polish pass), plus an EventKit meeting calendar with capture planning: arm a meeting, get prompted at start time, and captured notes carry a frozen meeting snapshot.

**Architecture:** Curation is two locked booleans on `ActionItem` (`userModified`/`isUserCreated`) that `FinalPolisher.apply` preserves, seeding `PointDedup` so AI near-duplicates drop. The calendar reads EventKit live through a fakeable `MeetingCalendarProviding` protocol; only two small SwiftData records persist (`PlannedCapture` for armed occurrences, `MeetingSnapshot` frozen onto notes at capture start). UI: the sidebar becomes a source list (Reviews / Archived / Calendar); calendar fills the content column with a month grid + day agenda; arming fires a user notification with a Start action plus an in-app prompt card.

**Tech Stack:** SwiftUI, SwiftData, EventKit, UserNotifications, Swift Testing.

## Global Constraints

- **Toolchain:** prefix every `xcodebuild` with `DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer` (system Xcode 26.5 lacks the macOS 27 SDK).
- **Test command (used in every task):**
  `DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' 2>&1 | grep -E "^\S*error:|✘|Test run|TEST (SUCCEEDED|FAILED)"`
  Success: `Test run with N tests ... passed` + `** TEST SUCCEEDED **`. Never use `-quiet`.
- **Baseline:** 55 tests in 10 suites pass before Task 1. Every task ends green.
- **Native-first UI** (user preference, 2026-07-07): native structural components (source lists, `NavigationSplitView`, popovers); glass/orb as accent only. Detail popups are **popovers anchored to rows**, never separate windows.
- **Never auto-record:** no code path may start listening without an explicit user action.
- **Synced groups:** new `.swift` files under `MyApp/`/`RevueAITests/` are picked up automatically; the only pbxproj edit is the calendar entitlement (Task 3).
- **No standalone `swift file.swift`:** script mode is broken on both toolchains; this plan has no scripts, keep it that way.
- `EKEvent` must never leak past `CalendarService`; everything downstream uses `MeetingEvent`.

---

### Task 1: Curation model fields + polish preservation

The contract everything else builds on: user-touched action items survive the final polish verbatim.

**Files:**
- Modify: `MyApp/Models/ActionItem.swift` (three new fields)
- Modify: `MyApp/AI/FinalPolisher.swift:97-130` (the `apply` action-items block)
- Test: `RevueAITests/FinalPolisherTests.swift` (append tests)

**Interfaces:**
- Consumes: existing `PointDedup.containsSimilar(_:in:)`, `PolishedActionItem`, `PolishedReview.stub`/`PolishedActionItem.stub` from `RevueAITests/Support/TestSupport.swift`.
- Produces: `ActionItem.tags: [String]`, `ActionItem.userModified: Bool`, `ActionItem.isUserCreated: Bool` (all with defaults, plus matching `init` parameters `tags: [String] = []`, `userModified: Bool = false`, `isUserCreated: Bool = false`). `FinalPolisher` preserves locked items. Tasks 2–5 rely on these fields.

- [ ] **Step 1: Write the failing tests**

Append inside the `FinalPolisherTests` struct in `RevueAITests/FinalPolisherTests.swift` (before its closing brace). Look at the file's existing tests first and reuse its setup helpers if it has them; these tests are written against the same `makeInMemoryContext`/`FakeReviewModel` conventions used elsewhere:

```swift
    @Test func userEditedItemsSurvivePolish() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let edited = ActionItem(oneLiner: "Ship the fix to production", order: 0, userModified: true)
        edited.note = note
        context.insert(edited)
        let untouched = ActionItem(oneLiner: "Old AI item", order: 1)
        untouched.note = note
        context.insert(untouched)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(actionItems: [
            .stub("Completely new item"),
        ]))]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [AudioSegment(speakerHint: .presenter, text: "hi", timestamp: .now)], context: context)
        #expect(note.sortedActionItems.map(\.oneLiner) == [
            "Ship the fix to production",
            "Completely new item",
        ])
    }

    @Test func aiNearDuplicateOfEditedItemIsDropped() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let edited = ActionItem(oneLiner: "Add retry logic to the upload path", order: 0, userModified: true)
        edited.note = note
        context.insert(edited)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(actionItems: [
            .stub("Add retry logic to upload path"),
            .stub("Add pagination to the list endpoint"),
        ]))]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [AudioSegment(speakerHint: .presenter, text: "hi", timestamp: .now)], context: context)
        #expect(note.sortedActionItems.map(\.oneLiner) == [
            "Add retry logic to the upload path",
            "Add pagination to the list endpoint",
        ])
    }

    @Test func userCreatedItemsSurvivePolish() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let manual = ActionItem(oneLiner: "Manually added task", order: 0, isUserCreated: true)
        manual.note = note
        context.insert(manual)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(actionItems: []))]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [AudioSegment(speakerHint: .presenter, text: "hi", timestamp: .now)], context: context)
        #expect(note.sortedActionItems.map(\.oneLiner) == ["Manually added task"])
    }

    @Test func preservedItemsKeepOrderBeforePolishedOnes() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let first = ActionItem(oneLiner: "Edited A", order: 3, userModified: true)
        first.note = note
        context.insert(first)
        let second = ActionItem(oneLiner: "Edited B", order: 7, userModified: true)
        second.note = note
        context.insert(second)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(actionItems: [.stub("New from AI")]))]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [AudioSegment(speakerHint: .presenter, text: "hi", timestamp: .now)], context: context)
        #expect(note.sortedActionItems.map(\.oneLiner) == ["Edited A", "Edited B", "New from AI"])
        #expect(note.sortedActionItems.map(\.order) == [0, 1, 2])
    }
```

Note: check how existing `FinalPolisherTests` construct `AudioSegment` — if the initializer signature differs (e.g. an `origin` parameter), copy the file's existing construction style for the segment argument.

- [ ] **Step 2: Run tests to verify they fail**

Run the Global Constraints test command.
Expected: build error — `extra arguments 'userModified'/'isUserCreated' in call` (the fields don't exist yet).

- [ ] **Step 3: Add the fields and the preservation logic**

In `MyApp/Models/ActionItem.swift`, add after `var isDone: Bool = false`:

```swift
    /// User-curation layer on top of the AI output.
    var tags: [String] = []
    /// Set by any user edit (text, priority, category, tags). Locked items
    /// survive the final polish verbatim.
    var userModified: Bool = false
    /// True for items the user added manually (also locked).
    var isUserCreated: Bool = false
```

Extend the `init` — add parameters (with defaults, after `isDone: Bool = false`):

```swift
        tags: [String] = [],
        userModified: Bool = false,
        isUserCreated: Bool = false,
```

and assignments alongside the others:

```swift
        self.tags = tags
        self.userModified = userModified
        self.isUserCreated = isUserCreated
```

In `MyApp/AI/FinalPolisher.swift`, inside `apply`, replace the action-item deletion line. Replace:

```swift
        for existing in note.actionItems ?? [] { context.delete(existing) }
```

with:

```swift
        // User-touched items are locked: they survive polish verbatim and
        // near-duplicate AI versions of them are dropped below.
        let preserved = (note.actionItems ?? [])
            .filter { $0.userModified || $0.isUserCreated }
            .sorted { $0.order < $1.order }
        for existing in note.actionItems ?? [] where !existing.userModified && !existing.isUserCreated {
            context.delete(existing)
        }
        for (index, item) in preserved.enumerated() { item.order = index }
```

Then change the insertion loop's seed and starting order. Replace:

```swift
        var seen: [String] = []
        var order = 0
```

with:

```swift
        var seen: [String] = preserved.map(\.oneLiner)
        var order = preserved.count
```

(The rest of the loop is unchanged — `PointDedup.containsSimilar` now also matches against preserved one-liners.)

- [ ] **Step 4: Run tests to verify they pass**

Run the Global Constraints test command.
Expected: `Test run with 59 tests in 10 suites passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyApp RevueAITests
git commit -m "feat: user-curated action items survive the final polish"
```

---

### Task 2: Curation UI — editable popover, tags, manual items

**Files:**
- Modify: `MyApp/Views/ItemPopup.swift` (`ActionItemDetail` becomes editable)
- Modify: `MyApp/Views/LayeredActionCard.swift` (edited dot, auto-open for new items)
- Modify: `MyApp/Views/ActionItemBoard.swift` ("Add action item" row)
- Modify: `MyApp/Models/ActionPriority.swift`, `MyApp/Models/ActionCategory.swift` (ensure `CaseIterable`)
- Create: `RevueAITests/ActionItemCurationTests.swift`

**Interfaces:**
- Consumes: Task 1's `tags`/`userModified`/`isUserCreated`.
- Produces: `ActionItem.allTags(in context: ModelContext) -> [String]` (distinct, sorted, for autocomplete). `ActionRow(item:isSelected:onToggleSelect:showDetailOnAppear:)` gains the new `showDetailOnAppear: Bool = false` parameter.

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/ActionItemCurationTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct ActionItemCurationTests {
    @Test func allTagsReturnsDistinctSortedTags() throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let a = ActionItem(oneLiner: "A", order: 0, tags: ["backend", "urgent"])
        a.note = note
        context.insert(a)
        let b = ActionItem(oneLiner: "B", order: 1, tags: ["urgent", "api"])
        b.note = note
        context.insert(b)
        try context.save()
        #expect(ActionItem.allTags(in: context) == ["api", "backend", "urgent"])
    }

    @Test func allTagsIsEmptyWhenNoTags() throws {
        let context = try makeInMemoryContext()
        #expect(ActionItem.allTags(in: context) == [])
    }
}
```

Note: `tags` was added to `init` in Task 1 after `isDone`; if the compiler complains about argument order, match the init's declared parameter order.

- [ ] **Step 2: Run tests to verify they fail**

Run the Global Constraints test command.
Expected: build error — `type 'ActionItem' has no member 'allTags'`.

- [ ] **Step 3: Implement `allTags` and check enum conformances**

Add to the bottom of `MyApp/Models/ActionItem.swift` (inside the class):

```swift
    /// Every distinct tag across all action items, sorted — the autocomplete
    /// source for the tag editor.
    static func allTags(in context: ModelContext) -> [String] {
        let items = (try? context.fetch(FetchDescriptor<ActionItem>())) ?? []
        return Set(items.flatMap(\.tags)).sorted()
    }
```

(`import SwiftData` is already present in the file.)

Open `MyApp/Models/ActionPriority.swift` and `MyApp/Models/ActionCategory.swift`. If either enum does not already declare `CaseIterable`, add it to its conformance list (e.g. `enum ActionPriority: String, Codable, CaseIterable, Identifiable`). The popover's pickers need `.allCases`.

- [ ] **Step 4: Make the popover editable**

In `MyApp/Views/ItemPopup.swift`, replace the whole `ActionItemDetail` struct with:

```swift
struct ActionItemDetail: View {
    @Bindable var item: ActionItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""
    @State private var allTags: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Picker("Priority", selection: $item.priority) {
                        ForEach(ActionPriority.allCases) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Picker("Category", selection: $item.category) {
                        ForEach(ActionCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
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

                TextField("What needs to happen", text: $item.oneLiner, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.display(17, .semibold))

                if !item.rationale.isEmpty {
                    DetailSection(title: "Why it matters", text: item.rationale, tint: item.priority.tint)
                }

                VStack(alignment: .leading, spacing: 6) {
                    DetailHeader(title: "In depth")
                    TextField("Add detail", text: $item.inDepthDetail, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Theme.rounded(13))
                }

                tagEditor

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

                HStack {
                    if !item.attribution.isEmpty {
                        Text("Raised by \(item.attribution)")
                            .font(Theme.rounded(11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        dismiss()
                        context.delete(item)
                        try? context.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(Theme.rounded(11, .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.85))
                }
            }
            .padding(16)
        }
        .frame(width: 380)
        .frame(maxHeight: 480)
        .onAppear { allTags = ActionItem.allTags(in: context) }
        .onChange(of: item.oneLiner) { markEdited() }
        .onChange(of: item.inDepthDetail) { markEdited() }
        .onChange(of: item.priority) { markEdited() }
        .onChange(of: item.category) { markEdited() }
        .onChange(of: item.tags) { markEdited() }
    }

    private func markEdited() {
        if !item.userModified { item.userModified = true }
        try? context.save()
    }

    // MARK: - Tags

    private var suggestions: [String] {
        guard !newTag.isEmpty else { return [] }
        return allTags.filter { $0.localizedCaseInsensitiveContains(newTag) && !item.tags.contains($0) }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailHeader(title: "Tags")
            FlowLayoutish {
                ForEach(item.tags, id: \.self) { tag in
                    HStack(spacing: 3) {
                        Text(tag)
                        Button {
                            item.tags.removeAll { $0 == tag }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .font(Theme.rounded(11, .medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.accent)
                }
                TextField("Add tag", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(Theme.rounded(11))
                    .frame(minWidth: 60, maxWidth: 100)
                    .onSubmit { addTag(newTag) }
            }
            if !suggestions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(suggestions.prefix(4), id: \.self) { suggestion in
                        Button(suggestion) { addTag(suggestion) }
                            .buttonStyle(.plain)
                            .font(Theme.rounded(11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func addTag(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !item.tags.contains(tag) else { newTag = ""; return }
        item.tags.append(tag)
        newTag = ""
    }
}

/// A minimal wrapping layout for tag chips.
struct FlowLayoutish: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(proposal: proposal, subviews: subviews)
        for (subview, position) in zip(subviews, arrangement.positions) {
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                          proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? 340
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + 6
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + 6
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
```

- [ ] **Step 5: Edited dot + auto-open on new rows**

In `MyApp/Views/LayeredActionCard.swift`:
- Add the parameter after `var onToggleSelect: () -> Void = {}`:

```swift
    var showDetailOnAppear = false
```

- Add after the priority-dot `Circle()` (as a sibling adornment on the one-liner `Text` line — place it immediately after the `Text(item.oneLiner)...frame(...)` modifier chain):

```swift
            if item.userModified || item.isUserCreated {
                Circle()
                    .fill(Theme.accent.opacity(0.9))
                    .frame(width: 5, height: 5)
                    .padding(.top, 5)
                    .help("Edited by you — polish won't overwrite it")
            }
```

- Add alongside the `.popover` modifier:

```swift
        .onAppear { if showDetailOnAppear { showDetail = true } }
```

In `MyApp/Views/ActionItemBoard.swift`:
- Add state to `ReviewBoard` after `@State private var selection: Set<UUID> = []`:

```swift
    @State private var newItemID: UUID?
```

- In `actionColumn`, pass the flag to `ActionRow` — replace:

```swift
                ActionRow(item: item, isSelected: selection.contains(item.id)) {
                    toggleSelect(item.id)
                }
```

with:

```swift
                ActionRow(item: item, isSelected: selection.contains(item.id),
                          onToggleSelect: { toggleSelect(item.id) },
                          showDetailOnAppear: item.id == newItemID)
```

- Reorder (spec: "reorder via drag persists order" — implemented as explicit move actions, which persist the same `order` field without a drag engine): extend the row's `.contextMenu` in `actionColumn`. Replace the existing context menu block:

```swift
                .contextMenu {
                    Button(item.isDone ? "Reopen" : "Mark complete") { apply([item.id], done: !item.isDone) }
                    Button(selection.contains(item.id) ? "Deselect" : "Select") { toggleSelect(item.id) }
                }
```

with:

```swift
                .contextMenu {
                    Button(item.isDone ? "Reopen" : "Mark complete") { apply([item.id], done: !item.isDone) }
                    Button(selection.contains(item.id) ? "Deselect" : "Select") { toggleSelect(item.id) }
                    Divider()
                    Button("Move up") { move(item, within: items, by: -1) }
                        .disabled(items.first?.id == item.id)
                    Button("Move down") { move(item, within: items, by: 1) }
                        .disabled(items.last?.id == item.id)
                }
```

and add to `ReviewBoard`:

```swift
    /// Swaps `order` with the neighbor in the same column; a user-initiated
    /// reorder locks the item like any other edit.
    private func move(_ item: ActionItem, within items: [ActionItem], by delta: Int) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              items.indices.contains(index + delta) else { return }
        let neighbor = items[index + delta]
        withAnimation(.smooth) {
            swap(&item.order, &neighbor.order)
            item.userModified = true
        }
        try? context.save()
    }
```

- In the To Do column only, add an "Add action item" row. Change the `actionColumn("To Do", ...)` call site: after the `ForEach(items) { ... }` content inside `BoardColumn`, the cleanest hook is a new optional `footer` slot. Give `BoardColumn` a footer: add to its properties:

```swift
    var footer: AnyView? = nil
```

render it after the `VStack(spacing: 8) { content }` (and also when empty, after the empty text):

```swift
            if let footer { footer }
```

then pass from the To Do call site only — `actionColumn` gains a `showsAddRow: Bool` parameter:

```swift
    private func actionColumn(_ title: String, systemImage: String, items: [ActionItem], markCompleted: Bool, emptyText: String, showsAddRow: Bool = false) -> some View {
        BoardColumn(title: title, systemImage: systemImage, count: items.count,
                    accent: markCompleted ? Color(red: 0.35, green: 0.85, blue: 0.55) : .secondary,
                    isEmpty: items.isEmpty, emptyText: emptyText,
                    dropAction: { ids in apply(ids, done: markCompleted) },
                    footer: showsAddRow ? AnyView(addItemRow) : nil) {
```

update the "To Do" call site to pass `showsAddRow: true`, and add to `ReviewBoard`:

```swift
    private var addItemRow: some View {
        Button {
            let item = ActionItem(
                oneLiner: "New action item",
                order: (note.actionItems?.map(\.order).max() ?? -1) + 1,
                isUserCreated: true
            )
            item.note = note
            context.insert(item)
            try? context.save()
            newItemID = item.id
        } label: {
            Label("Add action item", systemImage: "plus.circle")
                .font(Theme.rounded(12, .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
```

Note: `BoardColumn` is `private struct BoardColumn<Content: View>` — adding the `footer: AnyView?` property means every existing call site must either pass it or rely on the default; the default `= nil` keeps other columns unchanged.

- [ ] **Step 6: Run the full suite**

Run the Global Constraints test command.
Expected: `Test run with 61 tests in 11 suites passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Verify by hand**

```bash
DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer xcodebuild build -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' 2>&1 | grep -E "^\S*error:|BUILD" && open ~/Library/Developer/Xcode/DerivedData/RevueAI-*/Build/Products/Debug/RevueAI.app
```

Open a note with items: click a row → popover with editable text/pickers/tags; edit something → the accent dot appears on the row; "Add action item" creates a row whose popover opens itself; delete works. Stop-capture polish keeps edited items.

- [ ] **Step 8: Commit**

```bash
git add MyApp RevueAITests
git commit -m "feat: curation UI — editable popover, tags, manual items"
```

---

### Task 3: Calendar data layer

`CalendarService` behind a protocol, the two SwiftData records, snapshot stamping on capture start, attendee hints into the polish prompt, and the calendar entitlement.

**Files:**
- Create: `MyApp/Calendar/MeetingEvent.swift`
- Create: `MyApp/Calendar/CalendarService.swift`
- Create: `MyApp/Models/PlannedCapture.swift`
- Create: `MyApp/Models/MeetingSnapshot.swift`
- Create: `MyApp/Calendar/CapturePlanner.swift`
- Modify: `MyApp/Models/ReviewNote.swift` (to-one `meetingSnapshot`)
- Modify: `MyApp/RevueAIApp.swift:14-20` (schema)
- Modify: `RevueAITests/Support/TestSupport.swift:7-13` (schema)
- Modify: `MyApp/CaptureCoordinator.swift:90-113` (`start` gains `meeting:`)
- Modify: `MyApp/AI/FinalPolisher.swift:20-44` (attendee hint)
- Modify: `RevueAI.xcodeproj/project.pbxproj` (calendar entitlement, both app configs)
- Create: `RevueAITests/CapturePlannerTests.swift`
- Create: `RevueAITests/Support/FakeMeetingCalendar.swift`
- Test additions: `RevueAITests/CaptureCoordinatorTests.swift`, `RevueAITests/FinalPolisherTests.swift`

**Interfaces:**
- Consumes: `CaptureCoordinator.start(context:)`, `FinalPolisher.polish`, `LiveExtractor.knownPointsSummary`.
- Produces:
  - `struct MeetingEvent: Identifiable, Equatable, Sendable` — `id: String`, `seriesID: String`, `title: String`, `start: Date`, `end: Date`, `attendees: [String]`, `isRecurring: Bool`.
  - `enum CalendarAuthorization { case notDetermined, authorized, denied }`
  - `protocol MeetingCalendarProviding` — `var authorization: CalendarAuthorization { get }`, `func requestAccess() async -> Bool`, `func events(from: Date, to: Date) -> [MeetingEvent]`.
  - `@Model PlannedCapture` — `eventID: String`, `seriesID: String`, `occurrenceDate: Date`, `title: String`.
  - `@Model MeetingSnapshot` — `title: String`, `seriesID: String`, `occurrenceDate: Date`, `attendees: [String]`, `note: ReviewNote?`; `ReviewNote.meetingSnapshot: MeetingSnapshot?`.
  - `enum CapturePlanner` (`@MainActor` statics) — `isArmed(_:in:) -> Bool`, `arm(_:in:)`, `disarm(_:in:)`, `consume(eventID:occurrenceDate:in:) -> PlannedCapture?`, `prune(now:in:)`, `duePrompt(now:in:) -> PlannedCapture?`.
  - `CaptureCoordinator.start(context:meeting: MeetingEvent? = nil)`.

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/Support/FakeMeetingCalendar.swift`:

```swift
import Foundation
@testable import RevueAI

final class FakeMeetingCalendar: MeetingCalendarProviding {
    var authorization: CalendarAuthorization = .authorized
    var stubbedEvents: [MeetingEvent] = []

    func requestAccess() async -> Bool { authorization == .authorized }

    func events(from: Date, to: Date) -> [MeetingEvent] {
        stubbedEvents.filter { $0.start >= from && $0.start <= to }
    }
}

extension MeetingEvent {
    static func stub(
        id: String = "evt-1",
        seriesID: String = "series-1",
        title: String = "Design review",
        start: Date = .now.addingTimeInterval(3600),
        attendees: [String] = ["Priya", "Marcus"],
        isRecurring: Bool = false
    ) -> MeetingEvent {
        MeetingEvent(id: id, seriesID: seriesID, title: title,
                     start: start, end: start.addingTimeInterval(1800),
                     attendees: attendees, isRecurring: isRecurring)
    }
}
```

Create `RevueAITests/CapturePlannerTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

@MainActor
struct CapturePlannerTests {
    @Test func armCreatesAPlannedCapture() throws {
        let context = try makeInMemoryContext()
        let event = MeetingEvent.stub()
        CapturePlanner.arm(event, in: context)
        #expect(CapturePlanner.isArmed(event, in: context))
    }

    @Test func disarmRemovesIt() throws {
        let context = try makeInMemoryContext()
        let event = MeetingEvent.stub()
        CapturePlanner.arm(event, in: context)
        CapturePlanner.disarm(event, in: context)
        #expect(!CapturePlanner.isArmed(event, in: context))
    }

    @Test func armingIsIdempotent() throws {
        let context = try makeInMemoryContext()
        let event = MeetingEvent.stub()
        CapturePlanner.arm(event, in: context)
        CapturePlanner.arm(event, in: context)
        CapturePlanner.disarm(event, in: context)
        #expect(!CapturePlanner.isArmed(event, in: context))
    }

    @Test func consumeReturnsAndDeletesTheMatch() throws {
        let context = try makeInMemoryContext()
        let event = MeetingEvent.stub()
        CapturePlanner.arm(event, in: context)
        let consumed = CapturePlanner.consume(eventID: event.id, occurrenceDate: event.start, in: context)
        #expect(consumed != nil)
        #expect(!CapturePlanner.isArmed(event, in: context))
    }

    @Test func pruneDropsStaleCaptures() throws {
        let context = try makeInMemoryContext()
        let old = MeetingEvent.stub(id: "old", start: .now.addingTimeInterval(-7200))
        let upcoming = MeetingEvent.stub(id: "new", start: .now.addingTimeInterval(3600))
        CapturePlanner.arm(old, in: context)
        CapturePlanner.arm(upcoming, in: context)
        CapturePlanner.prune(now: .now, in: context)
        #expect(!CapturePlanner.isArmed(old, in: context))
        #expect(CapturePlanner.isArmed(upcoming, in: context))
    }

    @Test func duePromptReturnsMeetingThatJustStarted() throws {
        let context = try makeInMemoryContext()
        let due = MeetingEvent.stub(id: "due", start: .now.addingTimeInterval(-60))
        let later = MeetingEvent.stub(id: "later", start: .now.addingTimeInterval(3600))
        CapturePlanner.arm(due, in: context)
        CapturePlanner.arm(later, in: context)
        let prompt = CapturePlanner.duePrompt(now: .now, in: context)
        #expect(prompt?.eventID == "due")
    }
}
```

Append to `RevueAITests/CaptureCoordinatorTests.swift` (inside the struct — match the file's existing coordinator-construction style, which passes fake transcription services and a `FakeReviewModel`; copy the setup of an existing test that calls `coordinator.start`):

```swift
    @Test func startWithMeetingStampsSnapshotAndTitle() async throws {
        let context = try makeInMemoryContext()
        let model = FakeReviewModel()
        let coordinator = CaptureCoordinator(
            transcription: FakeTranscriptionService(),
            systemTranscription: FakeTranscriptionService(),
            model: model
        )
        coordinator.captureSystemAudio = false
        let meeting = MeetingEvent.stub(title: "Sprint review")
        CapturePlanner.arm(meeting, in: context)
        await coordinator.start(context: context, meeting: meeting)
        let notes = try context.fetch(FetchDescriptor<ReviewNote>())
        let note = try #require(notes.first)
        #expect(note.title == "Sprint review")
        #expect(note.meetingSnapshot?.attendees == ["Priya", "Marcus"])
        #expect(note.meetingSnapshot?.seriesID == "series-1")
        #expect(!CapturePlanner.isArmed(meeting, in: context))
        await coordinator.stop()
    }
```

(If the file's fake transcription type has a different name — e.g. `FakeTranscriptionService` doesn't exist but `ScriptedTranscriptionService` does — use the file's own type and construction style; the assertions stay the same. `import SwiftData` may need adding for `FetchDescriptor`.)

Append to `RevueAITests/FinalPolisherTests.swift`:

```swift
    @Test func polishPromptIncludesAttendeeHints() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let snapshot = MeetingSnapshot(title: "Review", seriesID: "s", occurrenceDate: .now, attendees: ["Priya", "Marcus"])
        snapshot.note = note
        context.insert(snapshot)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub())]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [AudioSegment(speakerHint: .presenter, text: "hi", timestamp: .now)], context: context)
        let call = try #require(model.polishCalls.first)
        #expect(call.livePoints.contains("Attendees: Priya, Marcus"))
    }
```

(Match `AudioSegment` construction and the `polishCalls` recording property to what `FakeReviewModel` actually exposes — it records polish inputs for existing tests; use the same property name.)

- [ ] **Step 2: Run tests to verify they fail**

Run the Global Constraints test command.
Expected: build errors — `cannot find type 'MeetingCalendarProviding'`, `cannot find 'CapturePlanner'`, etc.

- [ ] **Step 3: Implement the data layer**

Create `MyApp/Calendar/MeetingEvent.swift`:

```swift
import Foundation

/// A calendar meeting as the app sees it — a plain value decoupled from
/// EventKit so everything downstream is testable and `EKEvent` never leaks.
struct MeetingEvent: Identifiable, Equatable, Sendable {
    /// EventKit's per-occurrence event identifier.
    let id: String
    /// Stable across occurrences of a recurring series.
    let seriesID: String
    let title: String
    let start: Date
    let end: Date
    let attendees: [String]
    let isRecurring: Bool
}

enum CalendarAuthorization {
    case notDetermined
    case authorized
    case denied
}

/// Read-only meeting source. The production implementation wraps EventKit;
/// tests use a fake.
protocol MeetingCalendarProviding {
    var authorization: CalendarAuthorization { get }
    func requestAccess() async -> Bool
    func events(from: Date, to: Date) -> [MeetingEvent]
}
```

Create `MyApp/Calendar/CalendarService.swift`:

```swift
import Foundation
import EventKit

/// EventKit-backed meeting source. Reads are always live — Apple Calendar
/// owns syncing (Google/Exchange/iCloud/.ics). Republishes store-change
/// notifications so views can refresh.
@MainActor
final class CalendarService: MeetingCalendarProviding {
    private let store = EKEventStore()

    var authorization: CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func events(from: Date, to: Date) -> [MeetingEvent] {
        guard authorization == .authorized else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).map { event in
            MeetingEvent(
                id: event.eventIdentifier ?? UUID().uuidString,
                seriesID: event.calendarItemIdentifier,
                title: event.title ?? "Untitled",
                start: event.startDate,
                end: event.endDate,
                attendees: (event.attendees ?? []).compactMap(\.name),
                isRecurring: event.hasRecurrenceRules
            )
        }
        .sorted { $0.start < $1.start }
    }

    /// Fires whenever the underlying store changes (Apple Calendar synced).
    var changePublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
    }
}
```

(Add `import Combine` at the top if the compiler asks for it for `NotificationCenter.Publisher`.)

Create `MyApp/Models/PlannedCapture.swift`:

```swift
import Foundation
import SwiftData

/// One armed meeting occurrence: "prompt me to capture when this starts."
/// Created by the calendar's arm toggle; consumed when the capture starts
/// or pruned once the occurrence is long past.
@Model
final class PlannedCapture {
    var id: UUID = UUID()
    var eventID: String = ""
    var seriesID: String = ""
    var occurrenceDate: Date = Date()
    var title: String = ""

    init(eventID: String = "", seriesID: String = "", occurrenceDate: Date = .now, title: String = "") {
        self.eventID = eventID
        self.seriesID = seriesID
        self.occurrenceDate = occurrenceDate
        self.title = title
    }
}
```

Create `MyApp/Models/MeetingSnapshot.swift`:

```swift
import Foundation
import SwiftData

/// Meeting metadata frozen onto a note at capture start. History queries run
/// on snapshots, so captured meetings survive calendar-event deletion.
@Model
final class MeetingSnapshot {
    var id: UUID = UUID()
    var title: String = ""
    /// Stable across occurrences of a recurring series.
    var seriesID: String = ""
    var occurrenceDate: Date = Date()
    var attendees: [String] = []

    /// Inverse of `ReviewNote.meetingSnapshot`. Optional for CloudKit.
    var note: ReviewNote?

    init(title: String = "", seriesID: String = "", occurrenceDate: Date = .now, attendees: [String] = []) {
        self.title = title
        self.seriesID = seriesID
        self.occurrenceDate = occurrenceDate
        self.attendees = attendees
    }
}
```

In `MyApp/Models/ReviewNote.swift`, add near the other relationship properties (after `var actionItems: [ActionItem]? = []` block of relationships — match surrounding style):

```swift
    /// The meeting this note was captured from, if started from the calendar.
    var meetingSnapshot: MeetingSnapshot?
```

Create `MyApp/Calendar/CapturePlanner.swift`:

```swift
import Foundation
import SwiftData

/// Arm/disarm bookkeeping for planned captures. Matching is by event id +
/// occurrence date so each occurrence of a recurring meeting arms separately.
@MainActor
enum CapturePlanner {
    /// How long after start time an armed meeting still counts as "due".
    static let dueWindow: TimeInterval = 15 * 60
    /// Planned captures older than this get pruned.
    static let staleAfter: TimeInterval = 2 * 60 * 60

    static func plannedCapture(for event: MeetingEvent, in context: ModelContext) -> PlannedCapture? {
        let id = event.id
        let date = event.start
        var descriptor = FetchDescriptor<PlannedCapture>(
            predicate: #Predicate { $0.eventID == id && $0.occurrenceDate == date }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func isArmed(_ event: MeetingEvent, in context: ModelContext) -> Bool {
        plannedCapture(for: event, in: context) != nil
    }

    static func arm(_ event: MeetingEvent, in context: ModelContext) {
        guard !isArmed(event, in: context) else { return }
        let planned = PlannedCapture(eventID: event.id, seriesID: event.seriesID,
                                     occurrenceDate: event.start, title: event.title)
        context.insert(planned)
        try? context.save()
    }

    static func disarm(_ event: MeetingEvent, in context: ModelContext) {
        guard let planned = plannedCapture(for: event, in: context) else { return }
        context.delete(planned)
        try? context.save()
    }

    /// Removes and returns the planned capture for a starting meeting.
    @discardableResult
    static func consume(eventID: String, occurrenceDate: Date, in context: ModelContext) -> PlannedCapture? {
        var descriptor = FetchDescriptor<PlannedCapture>(
            predicate: #Predicate { $0.eventID == eventID && $0.occurrenceDate == occurrenceDate }
        )
        descriptor.fetchLimit = 1
        guard let planned = try? context.fetch(descriptor).first else { return nil }
        let copy = PlannedCapture(eventID: planned.eventID, seriesID: planned.seriesID,
                                  occurrenceDate: planned.occurrenceDate, title: planned.title)
        context.delete(planned)
        try? context.save()
        return copy
    }

    /// Drops planned captures whose occurrence is long past (event deleted,
    /// meeting missed — either way the prompt window is over).
    static func prune(now: Date, in context: ModelContext) {
        let cutoff = now.addingTimeInterval(-staleAfter)
        let all = (try? context.fetch(FetchDescriptor<PlannedCapture>())) ?? []
        for planned in all where planned.occurrenceDate < cutoff {
            context.delete(planned)
        }
        try? context.save()
    }

    /// The armed meeting that has just started (within the due window), if any.
    static func duePrompt(now: Date, in context: ModelContext) -> PlannedCapture? {
        let all = (try? context.fetch(FetchDescriptor<PlannedCapture>())) ?? []
        return all
            .filter { $0.occurrenceDate <= now && now.timeIntervalSince($0.occurrenceDate) <= dueWindow }
            .sorted { $0.occurrenceDate > $1.occurrenceDate }
            .first
    }
}
```

- [ ] **Step 4: Wire schemas, coordinator, and polish hint**

Schemas — in `MyApp/RevueAIApp.swift` add to the `Schema([...])` list:

```swift
                PlannedCapture.self,
                MeetingSnapshot.self,
```

and the same two lines in `RevueAITests/Support/TestSupport.swift`'s `Schema([...])`.

Coordinator — in `MyApp/CaptureCoordinator.swift`, change the signature:

```swift
    func start(context: ModelContext, meeting: MeetingEvent? = nil) async {
```

and after `let note = ReviewNote(title: Self.defaultTitle(), date: .now, status: .capturing)` / before `context.insert(note)`, stamp the snapshot:

```swift
        if let meeting {
            note.title = meeting.title
            let snapshot = MeetingSnapshot(title: meeting.title, seriesID: meeting.seriesID,
                                           occurrenceDate: meeting.start, attendees: meeting.attendees)
            context.insert(snapshot)
            snapshot.note = note
            CapturePlanner.consume(eventID: meeting.id, occurrenceDate: meeting.start, in: context)
        }
```

Polish hint — in `MyApp/AI/FinalPolisher.swift` `polish`, replace:

```swift
        let livePoints = LiveExtractor.knownPointsSummary(for: note)
```

with:

```swift
        var livePoints = LiveExtractor.knownPointsSummary(for: note)
        if let snapshot = note.meetingSnapshot, !snapshot.attendees.isEmpty {
            let hint = "Attendees: " + snapshot.attendees.joined(separator: ", ")
            livePoints = livePoints.isEmpty ? hint : livePoints + "\n" + hint
        }
```

Entitlement — in `RevueAI.xcodeproj/project.pbxproj`, in BOTH app-target configurations (`000000000000000111000000` and `000000000000000112000000`):
- change `ENABLE_RESOURCE_ACCESS_CALENDARS = NO;` to `ENABLE_RESOURCE_ACCESS_CALENDARS = YES;`
- add next to the other `INFOPLIST_KEY_` lines:

```
				INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription = "RevueAI shows your meetings so captures can be planned and titled. Events are never modified.";
```

- [ ] **Step 5: Run tests to verify they pass**

Run the Global Constraints test command.
Expected: `Test run with 69 tests in 12 suites passed`, `** TEST SUCCEEDED **` (6 planner + 1 coordinator + 1 polisher added).

- [ ] **Step 6: Commit**

```bash
git add MyApp RevueAITests RevueAI.xcodeproj/project.pbxproj
git commit -m "feat: calendar data layer — EventKit service, planned captures, meeting snapshots"
```

---

### Task 4: Source-list sidebar + calendar UI

**Files:**
- Create: `MyApp/Views/CalendarPane.swift`
- Create: `MyApp/Calendar/CalendarPaneModel.swift`
- Modify: `MyApp/Views/Shell/RootShellView.swift` (source list + section switching)
- Modify: `MyApp/Views/LibraryView.swift` (`showArchived` becomes a parameter; archive toolbar button removed)
- Create: `RevueAITests/CalendarPaneModelTests.swift`

**Interfaces:**
- Consumes: `MeetingCalendarProviding`, `CapturePlanner`, `MeetingSnapshot`, `MeetingEvent` (Task 3).
- Produces: `CalendarPaneModel` (`@MainActor @Observable`) — `init(calendar: any MeetingCalendarProviding)`, `var displayedMonth: Date`, `var selectedDay: Date`, `func monthDays() -> [Date?]` (42 cells, `nil` = leading/trailing blank), `func daysWithNotes(in context: ModelContext) -> Set<Int>` (day-of-month numbers with snapshots), `func agenda(in context: ModelContext) -> [AgendaEntry]`, `func stepMonth(by: Int)`; `struct AgendaEntry: Identifiable` — `let event: MeetingEvent`, `let note: ReviewNote?`, `let seriesNoteCount: Int`.

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/CalendarPaneModelTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

@MainActor
struct CalendarPaneModelTests {
    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, hour: Int = 10) -> Date {
        DateComponents(calendar: .current, year: year, month: month, day: dayOfMonth, hour: hour).date!
    }

    @Test func monthGridHasFortyTwoCells() {
        let model = CalendarPaneModel(calendar: FakeMeetingCalendar())
        model.displayedMonth = day(2026, 7, 1)
        let cells = model.monthDays()
        #expect(cells.count == 42)
        #expect(cells.compactMap { $0 }.count == 31)
    }

    @Test func agendaJoinsEventsToCapturedNotes() throws {
        let context = try makeInMemoryContext()
        let start = day(2026, 7, 15)
        let fake = FakeMeetingCalendar()
        fake.stubbedEvents = [
            MeetingEvent.stub(id: "e1", seriesID: "s1", title: "Sprint review", start: start),
            MeetingEvent.stub(id: "e2", seriesID: "s2", title: "1:1", start: start.addingTimeInterval(3600)),
        ]
        let note = ReviewNote(title: "Sprint review")
        context.insert(note)
        let snapshot = MeetingSnapshot(title: "Sprint review", seriesID: "s1", occurrenceDate: start)
        snapshot.note = note
        context.insert(snapshot)
        try context.save()

        let model = CalendarPaneModel(calendar: fake)
        model.displayedMonth = start
        model.selectedDay = start
        let agenda = model.agenda(in: context)
        #expect(agenda.count == 2)
        #expect(agenda[0].note?.title == "Sprint review")
        #expect(agenda[0].seriesNoteCount == 1)
        #expect(agenda[1].note == nil)
    }

    @Test func daysWithNotesMarksSnapshotDays() throws {
        let context = try makeInMemoryContext()
        let snapshot = MeetingSnapshot(title: "R", seriesID: "s", occurrenceDate: day(2026, 7, 9))
        context.insert(snapshot)
        try context.save()
        let model = CalendarPaneModel(calendar: FakeMeetingCalendar())
        model.displayedMonth = day(2026, 7, 1)
        #expect(model.daysWithNotes(in: context).contains(9))
        #expect(!model.daysWithNotes(in: context).contains(10))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the Global Constraints test command.
Expected: build error — `cannot find 'CalendarPaneModel' in scope`.

- [ ] **Step 3: Implement the model**

Create `MyApp/Calendar/CalendarPaneModel.swift`:

```swift
import Foundation
import Observation
import SwiftData

/// One meeting in the selected day's agenda, joined to its captured note
/// (by series id + occurrence date) and its series' capture history.
struct AgendaEntry: Identifiable {
    let event: MeetingEvent
    let note: ReviewNote?
    let seriesNoteCount: Int

    var id: String { event.id }
}

/// Month/agenda state for the calendar pane. Events are read live from the
/// provider; captured history joins against `MeetingSnapshot` records.
@MainActor
@Observable
final class CalendarPaneModel {
    var displayedMonth: Date = .now
    var selectedDay: Date = .now

    private let calendar: any MeetingCalendarProviding
    private let cal = Calendar.current

    init(calendar: any MeetingCalendarProviding) {
        self.calendar = calendar
    }

    var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    func stepMonth(by delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }

    /// 42 cells (6 weeks × 7 days); nil for blanks outside the month.
    func monthDays() -> [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstWeekday = cal.component(.weekday, from: interval.start)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let dayCount = cal.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in 0..<dayCount {
            cells.append(cal.date(byAdding: .day, value: day, to: interval.start))
        }
        while cells.count < 42 { cells.append(nil) }
        return Array(cells.prefix(42))
    }

    /// Day-of-month numbers in the displayed month that have captured notes.
    func daysWithNotes(in context: ModelContext) -> Set<Int> {
        guard let interval = cal.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<MeetingSnapshot>(
            predicate: #Predicate { $0.occurrenceDate >= start && $0.occurrenceDate < end }
        )
        let snapshots = (try? context.fetch(descriptor)) ?? []
        return Set(snapshots.map { cal.component(.day, from: $0.occurrenceDate) })
    }

    /// The selected day's meetings, joined to captured notes and series history.
    func agenda(in context: ModelContext) -> [AgendaEntry] {
        guard let interval = cal.dateInterval(of: .day, for: selectedDay) else { return [] }
        let events = calendar.events(from: interval.start, to: interval.end)
        let snapshots = (try? context.fetch(FetchDescriptor<MeetingSnapshot>())) ?? []
        return events.map { event in
            let match = snapshots.first {
                $0.seriesID == event.seriesID && cal.isDate($0.occurrenceDate, inSameDayAs: event.start)
            }
            let seriesCount = snapshots.filter { $0.seriesID == event.seriesID && $0.note != nil }.count
            return AgendaEntry(event: event, note: match?.note, seriesNoteCount: seriesCount)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Global Constraints test command.
Expected: `Test run with 72 tests in 13 suites passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Build the calendar pane and source-list sidebar**

Create `MyApp/Views/CalendarPane.swift`:

```swift
import SwiftUI
import SwiftData

/// The calendar surface: month grid over the selected day's agenda. Rows
/// join meetings to their captured notes and carry the arm toggle.
struct CalendarPane: View {
    var model: CalendarPaneModel
    /// Jumps to a captured note in the Reviews section.
    var onOpenNote: (ReviewNote) -> Void

    @Environment(\.modelContext) private var context
    @State private var refreshToken = 0

    var body: some View {
        Group {
            switch calendarAuthorization {
            case .authorized: content
            case .notDetermined, .denied: permissionState
            }
        }
        .navigationTitle("Calendar")
        .onAppear { CapturePlanner.prune(now: .now, in: context) }
    }

    private var calendarAuthorization: CalendarAuthorization {
        model.calendarProvider.authorization
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            monthHeader
            monthGrid
            Divider()
            agendaList
        }
    }

    private var monthHeader: some View {
        HStack {
            Text(model.monthTitle).font(.headline)
            Spacer()
            Button { model.stepMonth(by: -1) } label: { Image(systemName: "chevron.left") }
            Button { model.selectedDay = .now; model.displayedMonth = .now } label: { Text("Today") }
            Button { model.stepMonth(by: 1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var monthGrid: some View {
        let dotDays = model.daysWithNotes(in: context)
        let columns = Array(repeating: GridItem(.flexible()), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Calendar.current.veryShortWeekdaySymbols, id: \.self) { symbol in
                Text(symbol).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(Array(model.monthDays().enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, hasNotes: dotDays.contains(Calendar.current.component(.day, from: day)))
                } else {
                    Color.clear.frame(height: 28)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func dayCell(_ day: Date, hasNotes: Bool) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: model.selectedDay)
        let isToday = Calendar.current.isDateInToday(day)
        return Button {
            model.selectedDay = day
        } label: {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.callout.weight(isToday ? .bold : .regular))
                Circle()
                    .fill(hasNotes ? Theme.accent : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.25) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Agenda

    private var agendaList: some View {
        let entries = model.agenda(in: context)
        return List {
            if entries.isEmpty {
                Text("No meetings on \(model.selectedDay.formatted(date: .abbreviated, time: .omitted)).")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                AgendaRow(entry: entry, refreshToken: $refreshToken, onOpenNote: onOpenNote)
            }
        }
        .id(refreshToken)
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var permissionState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Calendar access needed")
                .font(.headline)
            Text("RevueAI shows your meetings so captures can be planned and titled. Events are never modified.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("Grant Access") {
                Task {
                    _ = await model.calendarProvider.requestAccess()
                    refreshToken += 1
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One meeting row: time, title, capture affordances.
private struct AgendaRow: View {
    let entry: AgendaEntry
    @Binding var refreshToken: Int
    var onOpenNote: (ReviewNote) -> Void

    @Environment(\.modelContext) private var context
    @State private var showHistory = false

    private var isUpcoming: Bool { entry.event.start > .now }

    /// Series capture history: every note snapshotted from this series.
    private var seriesHistory: some View {
        let seriesID = entry.event.seriesID
        let descriptor = FetchDescriptor<MeetingSnapshot>(
            predicate: #Predicate { $0.seriesID == seriesID },
            sortBy: [SortDescriptor(\.occurrenceDate, order: .reverse)]
        )
        let snapshots = ((try? context.fetch(descriptor)) ?? []).filter { $0.note != nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Captured from this series")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(snapshots) { snapshot in
                if let note = snapshot.note {
                    Button {
                        showHistory = false
                        onOpenNote(note)
                    } label: {
                        HStack {
                            Text(snapshot.occurrenceDate.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Image(systemName: "arrow.right").font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.event.title).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(entry.event.start.formatted(date: .omitted, time: .shortened))
                    if !entry.event.attendees.isEmpty {
                        Label("\(entry.event.attendees.count)", systemImage: "person.2")
                    }
                    if entry.event.isRecurring, entry.seriesNoteCount > 0 {
                        Button {
                            showHistory = true
                        } label: {
                            Label("\(entry.seriesNoteCount) notes", systemImage: "doc.text")
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showHistory, arrowEdge: .trailing) {
                            seriesHistory
                        }
                        .help("Capture history for this series")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let note = entry.note {
                Button {
                    onOpenNote(note)
                } label: {
                    Label("Note", systemImage: "doc.text.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .help("Open the captured note")
            } else if isUpcoming {
                Toggle("Arm", isOn: Binding(
                    get: { CapturePlanner.isArmed(entry.event, in: context) },
                    set: { armed in
                        if armed { CapturePlanner.arm(entry.event, in: context) }
                        else { CapturePlanner.disarm(entry.event, in: context) }
                        refreshToken += 1
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Prompt to start listening when this meeting begins")
            }
        }
        .padding(.vertical, 2)
    }
}
```

Add to `CalendarPaneModel` (needed by the pane for permission/refresh):

```swift
    var calendarProvider: any MeetingCalendarProviding { calendar }
```

In `MyApp/Views/Shell/RootShellView.swift`:
- Add the section enum at the top of the file (outside the struct):

```swift
enum LibrarySection: String, CaseIterable, Identifiable {
    case reviews, archived, calendar

    var id: String { rawValue }
    var label: String {
        switch self {
        case .reviews: "Reviews"
        case .archived: "Archived"
        case .calendar: "Calendar"
        }
    }
    var systemImage: String {
        switch self {
        case .reviews: "doc.text"
        case .archived: "archivebox"
        case .calendar: "calendar"
        }
    }
}
```

- Add state and the calendar model to the struct:

```swift
    @State private var section: LibrarySection = .reviews
    @State private var calendarModel = CalendarPaneModel(calendar: CalendarService())
```

- Restructure the `NavigationSplitView` to three columns:

```swift
        NavigationSplitView {
            List(LibrarySection.allCases, selection: Binding(
                get: { Optional(section) },
                set: { if let value = $0 { section = value } }
            )) { item in
                Label(item.label, systemImage: item.systemImage).tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } content: {
            switch section {
            case .reviews:
                LibraryPane(selection: $selection, showArchived: false)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320)
            case .archived:
                LibraryPane(selection: $selection, showArchived: true)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320)
            case .calendar:
                CalendarPane(model: calendarModel) { note in
                    section = .reviews
                    selection = note
                }
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
            }
        } detail: {
            readerContent
        }
```

In `MyApp/Views/LibraryView.swift` (`LibraryPane`):
- Replace `@State private var showArchived = false` with a parameter:

```swift
    let showArchived: Bool
```

- Delete the `.toolbar { ... }` archive button block and the `.onChange(of: showArchived)` handler (the section switch handles it — but keep re-selecting on section change by keeping `.onAppear { selection = shownNotes.first }`; change it from `selection = selection ?? shownNotes.first` to re-evaluate when archived doesn't contain selection — the existing `.onChange(of: shownNotes.count)` covers the rest).
- `navigationTitle` stays driven by `showArchived`.

- [ ] **Step 6: Run the full suite and verify by hand**

Run the Global Constraints test command.
Expected: `Test run with 72 tests in 13 suites passed`, `** TEST SUCCEEDED **`.

Build and launch (same command as Task 2 Step 7). Check: source list shows Reviews/Archived/Calendar; Calendar asks for access then shows the month + today's agenda; days with captured notes show dots (create a capture first if none); arm toggle flips on upcoming meetings; note badge jumps to the note in Reviews.

- [ ] **Step 7: Commit**

```bash
git add MyApp RevueAITests
git commit -m "feat: calendar pane with month grid, agenda, and arm toggles"
```

---

### Task 5: Arming prompts — notification + in-app card

**Files:**
- Create: `MyApp/Calendar/ArmedMeetingNotifier.swift`
- Modify: `MyApp/Views/Shell/RootShellView.swift` (in-app prompt card + notifier wiring)
- Modify: `MyApp/Views/CalendarPane.swift` (request notification auth on first arm)
- Create: `RevueAITests/ArmedMeetingNotifierTests.swift`

**Interfaces:**
- Consumes: `PlannedCapture`, `CapturePlanner.duePrompt(now:in:)`, `CaptureCoordinator.start(context:meeting:)`, `CalendarService`.
- Produces: `ArmedMeetingNotifier` (`@MainActor final class`) — `static func request(for: PlannedCapture) -> UNNotificationRequest`, `func ensureAuthorization() async`, `func sync(with context: ModelContext)`, `var onStartRequested: ((PlannedCapture) -> Void)?`; notification category `"ARMED_MEETING"` with action `"START_CAPTURE"`.

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/ArmedMeetingNotifierTests.swift`:

```swift
import Foundation
import Testing
import UserNotifications
@testable import RevueAI

@MainActor
struct ArmedMeetingNotifierTests {
    @Test func requestCarriesTitleTriggerAndCategory() {
        let planned = PlannedCapture(eventID: "e1", seriesID: "s1",
                                     occurrenceDate: Date(timeIntervalSince1970: 2_000_000_000),
                                     title: "Design review")
        let request = ArmedMeetingNotifier.request(for: planned)
        #expect(request.content.body.contains("Design review"))
        #expect(request.content.categoryIdentifier == "ARMED_MEETING")
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        #expect(trigger != nil)
        #expect(trigger?.nextTriggerDate() == nil || trigger!.nextTriggerDate()! >= .now)
        #expect(request.identifier == "armed-e1-2000000000")
    }

    @Test func requestIdentifierIsStablePerOccurrence() {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let a = ArmedMeetingNotifier.request(for: PlannedCapture(eventID: "e1", occurrenceDate: date, title: "A"))
        let b = ArmedMeetingNotifier.request(for: PlannedCapture(eventID: "e1", occurrenceDate: date, title: "B"))
        #expect(a.identifier == b.identifier)
    }
}
```

(`PlannedCapture(eventID:occurrenceDate:title:)` — the init has defaults for all parameters, so skipping `seriesID` compiles.)

- [ ] **Step 2: Run tests to verify they fail**

Run the Global Constraints test command.
Expected: build error — `cannot find 'ArmedMeetingNotifier' in scope`.

- [ ] **Step 3: Implement the notifier**

Create `MyApp/Calendar/ArmedMeetingNotifier.swift`:

```swift
import Foundation
import SwiftData
import UserNotifications

/// Schedules "your armed meeting started — start listening?" notifications
/// and routes the Start action back into the app. Listening never begins
/// without the user tapping Start (here or in the in-app prompt card).
@MainActor
final class ArmedMeetingNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let categoryID = "ARMED_MEETING"
    static let startActionID = "START_CAPTURE"

    /// Called with the planned capture when the user taps Start.
    var onStartRequested: ((PlannedCapture) -> Void)?

    private var modelContext: ModelContext?

    func activate(context: ModelContext) {
        modelContext = context
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: Self.startActionID,
                                         title: "Start listening",
                                         options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.categoryID,
                                              actions: [start],
                                              intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    func ensureAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Builds the notification for one planned capture. Identifier is stable
    /// per occurrence so re-syncing replaces rather than duplicates.
    static func request(for planned: PlannedCapture) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "RevueAI"
        content.body = "\(planned.title) started — start listening?"
        content.categoryIdentifier = categoryID
        content.userInfo = [
            "eventID": planned.eventID,
            "occurrence": planned.occurrenceDate.timeIntervalSince1970,
        ]
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: planned.occurrenceDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "armed-\(planned.eventID)-\(Int(planned.occurrenceDate.timeIntervalSince1970))"
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    /// Reconciles pending notifications with the current set of planned
    /// captures (call after arm/disarm changes and on launch).
    func sync(with context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        let planned = (try? context.fetch(FetchDescriptor<PlannedCapture>())) ?? []
        let wanted = planned.filter { $0.occurrenceDate > .now }
        center.removeAllPendingNotificationRequests()
        for capture in wanted {
            center.add(Self.request(for: capture))
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard response.actionIdentifier == Self.startActionID,
              let eventID = info["eventID"] as? String,
              let occurrence = info["occurrence"] as? TimeInterval else { return }
        await MainActor.run {
            guard let context = modelContext,
                  let planned = CapturePlanner.consumeMatch(eventID: eventID,
                                                            occurrence: Date(timeIntervalSince1970: occurrence),
                                                            in: context) else { return }
            onStartRequested?(planned)
        }
    }
}

extension CapturePlanner {
    /// Consume by raw ids (notification payload) — tolerant of sub-second
    /// date drift from the round-trip through userInfo.
    static func consumeMatch(eventID: String, occurrence: Date, in context: ModelContext) -> PlannedCapture? {
        let all = (try? context.fetch(FetchDescriptor<PlannedCapture>())) ?? []
        guard let planned = all.first(where: {
            $0.eventID == eventID && abs($0.occurrenceDate.timeIntervalSince(occurrence)) < 2
        }) else { return nil }
        let copy = PlannedCapture(eventID: planned.eventID, seriesID: planned.seriesID,
                                  occurrenceDate: planned.occurrenceDate, title: planned.title)
        context.delete(planned)
        try? context.save()
        return copy
    }
}
```

- [ ] **Step 4: Wire the prompt into the shell**

In `MyApp/Views/Shell/RootShellView.swift`, add state:

```swift
    @State private var notifier = ArmedMeetingNotifier()
    @State private var duePrompt: PlannedCapture?
```

Add wiring modifiers (alongside the existing `.onChange`/`.onAppear` handlers):

```swift
        .task {
            notifier.activate(context: context)
            notifier.onStartRequested = { planned in
                startFromPlanned(planned)
            }
            notifier.sync(with: context)
            // Poll for due armed meetings so the in-app card works even when
            // notifications are denied. 30s granularity is plenty.
            while !Task.isCancelled {
                if coordinator.state == .idle {
                    duePrompt = CapturePlanner.duePrompt(now: .now, in: context)
                } else {
                    duePrompt = nil
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
```

Add the in-app prompt card as an overlay on the `NavigationSplitView` (attach `.overlay(alignment: .bottom) { promptCard }`), plus the helpers:

```swift
    @ViewBuilder
    private var promptCard: some View {
        if let planned = duePrompt {
            HStack(spacing: 12) {
                OrbView(state: .idle, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(planned.title) started").font(Theme.rounded(13, .semibold))
                    Text("Start listening?").font(Theme.rounded(11)).foregroundStyle(.secondary)
                }
                Button("Start") {
                    let consumed = CapturePlanner.consumeMatch(eventID: planned.eventID,
                                                               occurrence: planned.occurrenceDate,
                                                               in: context)
                    startFromPlanned(consumed ?? planned)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    CapturePlanner.consumeMatch(eventID: planned.eventID,
                                                occurrence: planned.occurrenceDate, in: context)
                    duePrompt = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func startFromPlanned(_ planned: PlannedCapture) {
        duePrompt = nil
        let meeting = MeetingEvent(id: planned.eventID, seriesID: planned.seriesID,
                                   title: planned.title, start: planned.occurrenceDate,
                                   end: planned.occurrenceDate.addingTimeInterval(1800),
                                   attendees: [], isRecurring: false)
        Task { await coordinator.start(context: context, meeting: meeting) }
    }
```

In `MyApp/Views/CalendarPane.swift`, after each `CapturePlanner.arm(...)` call in the `AgendaRow` toggle binding, request notification permission and re-sync. `AgendaRow` gains a closure property:

```swift
    var onArmChanged: () -> Void = {}
```

call it after arm/disarm inside the toggle setter (`onArmChanged()` right after `refreshToken += 1`), and `CalendarPane` gains:

```swift
    var onArmChanged: () -> Void = {}
```

passed through to `AgendaRow(entry:refreshToken:onOpenNote:onArmChanged:)`. `RootShellView` supplies it:

```swift
                CalendarPane(model: calendarModel, onOpenNote: { note in
                    section = .reviews
                    selection = note
                }, onArmChanged: {
                    Task {
                        await notifier.ensureAuthorization()
                        notifier.sync(with: context)
                    }
                })
```

- [ ] **Step 5: Run the full suite**

Run the Global Constraints test command.
Expected: `Test run with 74 tests in 14 suites passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Verify by hand**

Build and launch. In Calendar, arm an upcoming meeting → notification permission prompt appears (first time). To test the prompt without waiting: create a calendar event starting 1–2 minutes from now in Apple Calendar, arm it in RevueAI, wait for the start time → the notification fires with a "Start listening" action AND the in-app card appears at the window bottom; tapping Start begins a capture titled after the meeting.

- [ ] **Step 7: Commit**

```bash
git add MyApp RevueAITests
git commit -m "feat: armed meetings prompt to start via notification and in-app card"
```

---

## Final verification (after Task 5)

- [ ] Full suite: the Global Constraints test command → `** TEST SUCCEEDED **`, 74 tests in 14 suites.
- [ ] Build: `DEVELOPER_DIR=/Users/shouryathakur/Desktop/Xcode-beta.app/Contents/Developer xcodebuild build -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS'` → `** BUILD SUCCEEDED **`.
- [ ] Manual walkthrough (needs the user): grant calendar access → arm a meeting 2 minutes out → get prompted at start → Start → note is titled after the meeting → stop → edit an action item + add a tag + add a manual item → re-check after polish that edits survived → confirm the note badge appears on that meeting in the calendar.
