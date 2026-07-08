# Onboarding v2: Glass Sheet + Two-Act Guided Tour

**Status:** Approved 2026-07-08

## Goal

Replace the stale TourKit onboarding with a design-current experience: a
custom glass welcome sheet whose slides render live SwiftUI illustrations,
followed by a guided in-app tour that points at the real controls — split
into two acts so curation is taught the moment a real note exists.

## Context

Onboarding already exists (`MyApp/Onboarding/OnboardingSheet.swift` +
`OnboardingPages.swift`): a TourKit slideshow with pre-rendered PNG art,
a permissions phase, and `hasCompletedOnboarding` gating in
`RootShellView`. It predates the app-wide redesign — the art shows the
old UI, the copy stops at "hit the orb", and nothing covers the board,
tags, assistant search, calendar arming, or the date ruler.

Capture starts from the **menu bar** (MenuBarExtra), not an in-window
button; the library empty state says "Start a capture from the menu bar."
The toolbar search field and export menu are AppKit `NSToolbar` items
(SwiftUI anchor preferences cannot see them), but the existing
`ToolbarSearchCenterer` probe already locates both.

## Decisions (made during brainstorming)

1. **Scope:** refresh the sheet AND add an in-app tour.
2. **Tour style:** guided step-by-step with a dimmed spotlight backdrop —
   custom SwiftUI, not TipKit (no sequencing/spotlight, stock styling).
3. **Two acts:** Act 1 right after the sheet (empty-state UI only);
   Act 2 fires once when the first note with action items opens. No
   seeded sample note.
4. **Drop TourKit:** remove the SwiftPM package, `Tools/render-tour-art.swift`,
   and `Resources/TourArt/*.png`. Slides are live SwiftUI views —
   always design-current, adaptive to light/dark.

## Flow

```
first launch
  └─ welcome sheet (5 slides → permissions) ── skippable
       └─ on dismiss: hasCompletedOnboarding = true, Act 1 starts
            └─ Act 1: search → date ruler → centered "menu bar" card
                 └─ hasSeenMainTour = true
...user captures their first review...
first open of a note that has action items (hasSeenBoardTour == false)
  └─ Act 2: To Do column → action item row → export menu
       └─ hasSeenBoardTour = true
```

- Esc or "Skip tour" ends the current act immediately (flags still set —
  skipping counts as seen).
- Settings "Replay tour" resets all three flags; the sheet re-presents
  and the acts re-arm.
- Closing the sheet at any point leaves the app fully usable (unchanged
  invariant).

## Components

### 1. `MyApp/Onboarding/OnboardingPages.swift` (rewrite)

Plain data, testable, as today. Five slides; each case names a live
illustration the sheet renders:

| # | Title | Illustration (live SwiftUI) |
|---|-------|------------------------------|
| 1 | Meet RevueAI | current orb (`OrbView`) — automatically becomes the Siri orb when that lands |
| 2 | Nothing is ever recorded | shield glyph treatment, privacy copy |
| 3 | Talk, and the note builds itself | miniature reader mock: stat chips + two board rows |
| 4 | Your meetings, on a ruler | non-interactive mini `DateRulerView` |
| 5 | Ask your notes anything | mock centered search field with a sample question |

### 2. `MyApp/Onboarding/OnboardingSheet.swift` (rewrite)

Custom paged glass sheet (no TourKit): page dots, Continue/Skip,
then the existing permissions phase (mic request + System Audio
settings link) restyled with the current glass-capsule language.
Final button: "Start my first capture" (existing `onStartCapture`
hook, unchanged).

### 3. `MyApp/Onboarding/TourModel.swift` (new)

- `TourStop`: `id`, `title`, `body`, `anchorID: String?` (nil = centered
  card), `arrowEdge`.
- `TourController` (`@Observable`): the stop sequence, current index,
  `advance()`, `skip()`, completion callback that sets the act's flag.
- Static definitions for Act 1 and Act 2 stop lists.

### 4. `MyApp/Onboarding/TourOverlay.swift` (new)

- `.tourAnchor(_ id: String)` view modifier registers a control's frame
  via anchor preferences.
- `TourOverlay` sits at the shell root: dimmed backdrop with a soft
  rounded cutout over the current stop's rect, plus a glass callout
  card (small-caps step counter, title, body, Next/Skip) positioned
  beside the target.
- Accepts rects from two sources: SwiftUI anchor preferences, and
  AppKit rects (search field / export menu located by the existing
  `ToolbarSearchCenterer` probe, converted to window coordinates).

### 5. Integration points

- `RootShellView`: hosts `TourOverlay`; starts Act 1 after the sheet
  dismisses; `.tourAnchor` on the date-ruler dock; passes AppKit rects
  for search + export.
- `NoteDetailView` / `ActionItemBoard`: `.tourAnchor` on the To Do
  column and the first action row; Act 2 trigger when a note with
  action items appears and `hasSeenBoardTour == false`.
- `SettingsView`: single "Replay tour" resets all three flags.
- `RevueAI.xcodeproj`: remove TourKit package reference; delete
  `Tools/render-tour-art.swift` and `MyApp/Resources/TourArt/`.

## Tour stops

**Act 1** (main window, empty state):
1. Search field — "Ask across every review" (AppKit rect).
2. Date ruler — "Scrub your history, filter by day, arm upcoming
   meetings" (SwiftUI anchor).
3. Centered card (no anchor) — "Capture lives in your menu bar", with a
   **Start a capture** button.

**Act 2** (first real note):
1. To Do column — "Drag items between columns to complete them"
   (SwiftUI anchor).
2. First action item row — "Click for details — your edits survive the
   AI's final polish" (SwiftUI anchor).
3. Export menu — "Share the finished note as Markdown" (AppKit rect).

## Persistence

`@AppStorage`: existing `hasCompletedOnboarding`, new `hasSeenMainTour`,
new `hasSeenBoardTour`. Skip sets the same flag as finish.

## Error handling

- An anchor that never registers (layout change, collapsed sidebar):
  the stop renders as a centered card instead of pointing at nothing.
- Permissions behave exactly as today: denial never blocks; the sheet
  can always be dismissed.

## Testing

Unit tests (XCTest, existing suite):
- Slide data: five slides, non-empty title/subtitle, unique ids.
- Stop data: both acts non-empty, unique stop ids, Act 1 ends with the
  centered capture card.
- `TourController`: `advance()` walks the sequence and fires completion
  at the end; `skip()` fires completion immediately; completion sets
  the right flag.
- Act 2 trigger predicate: fires only for a note with action items and
  `hasSeenBoardTour == false`.

Overlay visuals, spotlight geometry, and the AppKit rect handoff are
verified manually — no snapshot machinery.

## Out of scope

- TipKit long-tail tips (tags, arming from the agenda popover, series
  history) — possible follow-up.
- Localization of tour copy.
- Seeded sample data.
