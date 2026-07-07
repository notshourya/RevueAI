# RevueAI UI Redesign — Design Spec

**Date:** 2026-07-07
**Status:** Approved (brainstorm 2026-07-07)
**Scope:** App-wide visual redesign — glass shell with parallel panels, orb
capture identity, first-run onboarding. No pipeline changes.

## What & why

RevueAI's current UI is a conventional sidebar→detail Mac app. This redesign
gives the app a distinctive identity worthy of its differentiator (private,
zero-recording meeting capture): Liquid Glass surfaces on a dark backdrop,
a Siri-like animated orb as the face of "listening," and a guided first-run
tour that lands the privacy story and the two tricky permissions.

This spec was decomposed out of a larger brainstorm (calendar integration,
action-item curation, Jira positioning). Sequencing decision: **redesign
first** — building new feature surfaces on the old shell means building them
twice. Decisions already made for the follow-up spec are recorded in
*Deferred: Spec B* below so they aren't lost.

## Shell & layout

**Window structure.** One main window on a near-black backdrop. Three parallel
glass panels — **Library | Reader | Live** — each a `.glassEffect()` surface,
separated by draggable dividers: size-adjustable, sensible minimum widths,
sizes persisted across launches. Any panel collapses from its header; the Live
panel auto-expands when a capture starts. All three sit in one
`GlassEffectContainer` so the glass reads as a single system. The
sidebar→detail navigation is removed; Library selection drives Reader, and
Live is independent of both.

**Detail popups.** Clicking an action item, decision, or open question opens a
**separate glass window** (SwiftUI `openWindow` with a value-based
`WindowGroup`, borderless, glass background) showing full detail: one-liner,
rationale, in-depth section, quotes, attribution. Multiple popups can be open
simultaneously — they are real windows that can sit beside an editor while the
user works through review items. In this spec they are read-only; Spec B adds
tag/priority editing in this same surface.

**Menu bar.** Role unchanged (control center: start/stop, live indicator);
restyled to match the new identity.

**Aesthetic direction: dark-first signature look.** The brand look is the orb
on near-black with glass panels as the light-catching layer. Light mode remains
supported (standard adaptive materials) but the identity, marketing, and
default experience are dark.

## Orb identity

**Component.** A custom SwiftUI `OrbView(state:level:)` — layered radial
gradients, a moving specular highlight, and a soft chromatic rim, animated via
`TimelineView` so it breathes continuously. Custom-drawn (no third-party
package, no Metal shader): zero dependencies for the brand centerpiece, and
this style of layered-gradient orb is within SwiftUI's rendering budget.

**States:**
- **idle** — slow breathing
- **listening** — rim pulses with the live mic level (the orb visibly hears)
- **extracting** — brief internal shimmer when the live pass fires
- **error** — dims to grey

State is driven by `CaptureCoordinator`; the mapping is a small pure state
machine so it is unit-testable with a fake coordinator.

**Floating presence.** When capture starts, a small (~80 pt) always-on-top,
non-activating, borderless panel fades in with the orb — visible over Zoom or
an editor, draggable, position remembered. Click opens the main window's Live
panel; right-click offers Stop / Open. It disappears when capture ends. It
supplements (not replaces) the menu-bar indicator and can be disabled in
Settings.

**In-app and identity.** The Live panel renders the same orb large at its top
(orb-on-black composition). Onboarding's welcome slide uses it full-bleed. The
app icon is refreshed to an orb rendering so the identity carries through
Dock, notifications, and marketing.

## Onboarding

**TourKit** (SPM: github.com/rampatra/TourKit — SwiftUI+AppKit, macOS 13+,
zero dependencies, MIT), presented in its floating window on first launch.
Five slides:

1. **Orb welcome** — the brand moment.
2. **Zero-recording privacy story** — why this app is trustable in meetings.
3. **Mic permission** — triggers the system prompt inline.
4. **System-audio permission** — guided: deep link into Privacy & Security →
   Screen & System Audio Recording, plus a "verify it worked" check.
5. **Start your first capture** — arms the orb and hands off.

Skippable at any slide; re-runnable from Settings. Capture works with whatever
permissions were granted (the existing mic-only banner behavior is unchanged).

## Resilience & accessibility

- **Glass is presentation-only.** Every `.glassEffect()` surface has a
  plain-material fallback; no behavior depends on glass. (Glass rendering has
  varied across macOS 26/27 betas.)
- The floating orb window falls back to a standard panel if borderless glass
  misrenders.
- TourKit failing to load never blocks first capture — onboarding errors
  degrade to opening the main window with the permission-banner flow.
- **Reduce Transparency** switches glass to opaque materials; **Reduce
  Motion** stops the orb's continuous animation (static gradient, discrete
  state changes).

## Testing

UI-heavy spec, so unit coverage targets the state seams:

- Orb state machine: fake coordinator state sequence → expected `OrbState`
  sequence.
- Panel layout state persists and restores.
- Onboarding completion flag prevents re-showing.
- The existing pipeline test suite (43 tests) stays green throughout — the
  redesign must not touch the pipeline.

Visual quality (glass, animation feel, dark identity) is verified manually
against this spec.

## Phasing

1. **Shell** — parallel glass panels, dark identity, detail popup windows.
2. **Orb** — `OrbView` component, coordinator-driven states, floating window.
3. **Onboarding** — TourKit dependency, five slides, app icon refresh.

Each phase lands independently on main.

## Non-goals

- No pipeline, extraction, or data-model changes.
- No calendar or curation features (Spec B).
- No iOS companion.

## Deferred: Spec B (calendar + action-item curation)

Decisions already validated in the 2026-07-07 brainstorm, to seed the next
spec:

- **Positioning: bridge to trackers.** RevueAI is the system of record for
  review *conversations* (decisions, rationale, quotes) and pushes action
  items into Jira/GitHub with backlinks. It complements trackers, never
  competes. Jira connector gets its own later design (pattern mirrors the
  Phase 5 GitHub connector).
- **Calendar = meetings + notes + capture planning.** EventKit-backed
  (`CalendarService` behind a `MeetingCalendarProviding` protocol exposing
  `MeetingEvent` value types). Read-focused; no event CRUD.
- **Data architecture: live reads + capture snapshot.** UI reads EventKit
  live; starting a capture freezes a `MeetingSnapshot` (title, series ID,
  occurrence date, attendee names) onto the note. `PlannedCapture` records
  armed occurrences. No sync engine.
- **Armed meetings prompt to start** — never unattended listening.
- **Action-item curation: full.** Tags (free strings + autocomplete), edit
  text/priority/category, done state, delete, reorder, manual items.
  `ActionItem` gains `tags`, `isDone`, `userModified`, `isUserCreated`.
- **User edits always survive polish.** `FinalPolisher` preserves
  user-touched/user-created items verbatim, seeds `PointDedup` with their
  one-liners, and replaces only untouched AI items.
- Attendee names from the calendar seed the speaker-roster prompts.
