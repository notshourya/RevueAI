# RevueAI Calendar + Action-Item Curation — Design Spec (Spec B)

**Date:** 2026-07-07
**Status:** Approved (brainstorm 2026-07-07; UI revised same day after the
native-structure pivot)
**Scope:** Built-in meeting calendar (EventKit) with capture planning, and
user curation of AI-extracted action items. Follows the UI redesign
(`2026-07-07-ui-redesign-design.md`); its *Deferred: Spec B* section recorded
these decisions.

## Positioning (context, not build scope)

RevueAI is the system of record for review *conversations* — decisions,
rationale, quotes — and a **bridge to trackers**, never a replacement for
them. Action items curated here are what a future Jira/GitHub connector
pushes out as tickets with backlinks (pattern mirrors the roadmap's Phase 5
GitHub connector; the Jira connector gets its own later spec). Curation
exists so a spoken one-liner becomes ticket-ready before it's pushed.

## Part 1 — Calendar

### Job

Meetings + their notes + capture planning. Read-focused: no event creation
or editing (Apple Calendar owns that). The differentiator is events⊕notes.

### Data architecture: live reads + capture snapshot

- **`CalendarService`** (`@MainActor`, behind a `MeetingCalendarProviding`
  protocol so tests can fake it) wraps EventKit: requests access, fetches
  events for a date window across all calendars, republishes
  `EKEventStoreChanged` so views refresh when Apple Calendar syncs. It
  exposes plain **`MeetingEvent`** value structs (id, series id, title,
  start/end, attendee display names, isRecurring) — `EKEvent` never leaks
  downstream. Google/Exchange/iCloud/.ics sync is Apple Calendar's problem.
- **`PlannedCapture`** (SwiftData): one per armed occurrence — `eventID`,
  `occurrenceDate`, created when the user arms a meeting, deleted when the
  capture starts or the occurrence passes.
- **`MeetingSnapshot`** (SwiftData): frozen onto a `ReviewNote` at capture
  start — event title, `seriesID` (stable across recurrences), occurrence
  date, attendee names. Notes without one behave exactly as today. History
  queries run on snapshots (only captured meetings — what Review Assistant
  cares about); future/agenda reads are always live. No sync engine, no
  orphaned IDs: deleted calendar events can't take captured history with
  them.
- **Attendee names** from the snapshot are passed into the extraction
  prompts as speaker-roster hints (improves the final pass's named roster).

### UI (native structure)

- **Sidebar becomes a source list**: **Reviews**, **Archived**, **Calendar**
  (archived stops being a toolbar toggle). Reviews/Archived show the
  existing note list; Calendar fills the detail area.
- **Calendar detail**: a native month grid (dots on days with captured
  notes) over a day agenda list. Each agenda row shows title, time,
  attendee count, plus:
  - a **note badge** when that occurrence was captured — click jumps to the
    note in Reviews;
  - an **arm toggle** on upcoming occurrences (creates/deletes
    `PlannedCapture`);
  - on recurring events, a disclosure with the series' capture history
    ("Sprint review — 12 notes").
- **Permission empty state**: Calendar access not granted → explainer +
  grant button (EventKit full-access request), falling back to a deep link
  into System Settings if denied.

### Arming → prompt, never auto-record

When an armed meeting's start time arrives, a local user notification
fires — "*<event title>* started — start listening?" — with a **Start**
action; the menu-bar icon pulses until dismissed or started. Starting from
the prompt stamps the `MeetingSnapshot`, titles the note from the event, and
begins capture. Listening never starts without an explicit user action —
consistent with the zero-recording trust story.

## Part 2 — Action-item curation

### Model

`ActionItem` gains:
- `tags: [String]` — free strings; autocomplete sourced from a distinct-tags
  query across all notes (no separate Tag model — YAGNI).
- `userModified: Bool` — set by any edit (text, priority, category, tags).
- `isUserCreated: Bool` — set on manually added items.
- (`isDone` already exists.)

### Polish-pass contract: user edits always win

`FinalPolisher.apply` changes from delete-all to:
1. Preserve items where `userModified || isUserCreated` verbatim.
2. Seed `PointDedup`'s seen-list with the preserved items' one-liners, so
   the model's near-duplicate of an edited item is dropped.
3. Delete only untouched AI items; insert the polished set after the
   preserved ones (order continues from the preserved block).

Decisions and open questions keep replace-all behavior — curation is
action-items-only for now, since action items are what feed the tracker
bridge.

### UI

Curation happens in the **anchored popovers** (established 2026-07-07 —
popovers, not windows):
- Action-item popover: editable one-liner and in-depth text, priority and
  category pickers, tag chips with an autocomplete add-field, delete button,
  done toggle (existing).
- The board keeps drag-to-complete; reorder via drag persists `order`.
- "Add action item" row at the bottom of the To Do column creates a manual
  item (born `isUserCreated`, opens its popover for editing).
- User-touched items show a subtle "edited" dot in their row — the visible
  promise that polish won't overwrite them.

## Error handling

- EventKit access denied → calendar shows the permission empty state;
  everything else works.
- Event deleted after arming → the `PlannedCapture` is pruned on next
  calendar load; no prompt fires.
- Notification permission denied → arming still works; the prompt falls back
  to the menu-bar pulse only.
- Snapshot stamping failure never blocks capture start (snapshot is
  best-effort metadata).

## Testing

- `PlannedCapture` arm/disarm/prune logic against a fake
  `MeetingCalendarProviding`.
- Snapshot stamping: starting a capture from a `MeetingEvent` stamps title,
  series id, attendees onto the note.
- Polish preservation: user-modified and user-created items survive
  `FinalPolisher.apply`; near-duplicate AI items are dropped; untouched AI
  items are replaced (extends existing `FinalPolisherTests`).
- Tag/curation model: edits set `userModified`; distinct-tag autocomplete
  query returns expected sets.
- Calendar UI (month grid math, agenda joins) at the view-model seam with
  fake events; visual checks manual.

## Non-goals

- No event CRUD, no invites, no scheduling.
- No Jira connector yet (separate spec; positioning above).
- No curation of decisions/open questions.
- No level-reactive orb (still deferred).

## Phasing

1. **Curation** — model fields + polish preservation + popover editing
   (ships value alone, needed by the future bridge).
2. **Calendar data layer** — `CalendarService`, `MeetingEvent`,
   `PlannedCapture`, `MeetingSnapshot`, snapshot-on-capture.
3. **Calendar UI + arming** — source-list sidebar, month/agenda detail,
   notification prompt.
