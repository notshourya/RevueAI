# ReviewScribe — Design Spec

**Date:** 2026-07-04
**Platform:** macOS 27 only (Swift/SwiftUI)
**Build requirements:** Xcode 27 beta + macOS 27 developer beta (dev machine is
on macOS 26.4 / Xcode 26.5 as of writing — both must be upgraded before
implementation starts; the OS 27 APIs this app is built on — PCC developer API,
new Foundation Models, `LanguageModel` protocol — don't exist in the 26 SDK)
**Working name:** ReviewScribe (final name TBD before ship, not before build)

## What it is

A macOS app that captures technical reviews and standups as structured, actionable
notes — without ever recording audio. Hit a global shortcut (or ask Siri) when a
review starts; the app listens, transcribes on-device, tells speakers apart, and
extracts the points that matter in real time. When the meeting ends, a private
cloud pass polishes everything into a review note: summary & verdict, concrete
action items (each with an in-depth subsection), and open questions.

Works for online meetings (Zoom/Meet/Teams — any app, via system audio capture)
and in-person standups (mic). Notes sync via iCloud and can be shared with
teammates on Macs.

## Why (problem)

In technical reviews, important feedback is spoken, not written. Action items and
conditions get missed or forgotten after the meeting. Recording meetings is a
privacy problem; manual note-taking splits the presenter's attention. This app
captures the outcome of the review with zero recording and zero note-taking effort,
and produces output an AI coding agent can act on directly.

## Form factor

A full Mac app **plus** a menu bar companion (like Fantastical):

- **Main window** — the notes library: sidebar of past review notes, search,
  full reading view with expandable in-depth sections, export.
- **Menu bar item** — always-available capture surface: start/stop listening,
  discreet "listening" indicator, compact live panel showing points as they are
  extracted. Starting a session never requires the main window.

## Architecture

### Capture & transcription pipeline

Two parallel audio streams, both transcribed live and on-device by
`SpeechAnalyzer`/`SpeechTranscriber` (Speech framework):

1. **Mic stream** (`AVAudioEngine`) → default speaker hint: **Presenter/You**
2. **System audio stream** (Core Audio process taps, macOS 14.4+ API) → remote
   participants → default speaker hint: **Reviewer**

Each finalized transcript segment becomes `(speakerHint, text, timestamp)` in an
**in-memory rolling transcript**. Audio buffers flow capture → transcriber →
discarded; audio is never written to disk. The transcript itself is discarded
after the final extraction pass. Only the structured note persists. This is
enforced by design (no code path persists audio or transcript), not by a setting.

### Speaker attribution

Behind a `SpeakerAttribution` protocol:

- **MVP implementation:** stream-of-origin (mic vs system audio) + LLM context
  refinement — the model distinguishes "Reviewer 1" from "Reviewer 2" using
  conversational context and names spoken aloud. Known limitation: fully in-room
  meetings arrive on one mic stream, so MVP attribution there is context-only
  and imperfect.
- **Phase 4 implementation:** FluidAudio (open-source Swift/CoreML) voice
  diarization slots in behind the same protocol — true voice-based separation
  for in-room meetings. No other component changes.

### AI extraction — two-model design

Both passes talk to the `LanguageModel` protocol (Foundation Models framework),
so backends are swappable without pipeline changes ("dynamic profiling").

- **Live pass — on-device `SystemLanguageModel`.** Every ~30–45s (or every N
  finalized segments), the new transcript chunk + the compact list of
  already-extracted points go to the on-device model. Guided generation
  (`@Generable` structs) returns typed candidates — `ActionItem`, `Decision`,
  `OpenQuestion` — each with confidence and supporting quote. New points stream
  into the live panel. Fits the on-device context window because only the fresh
  chunk + existing points are sent.
- **Final pass — `PrivateCloudComputeLanguageModel`** (32K context, reasoning
  enabled; no API keys; free under 2M downloads). On stop, the entire in-memory
  transcript + live-extracted points go up in one request. PCC dedupes, merges,
  fixes speaker attribution with full-conversation context, writes the summary
  & verdict, and writes each action item's in-depth subsection.
- **Offline fallback:** if PCC is unreachable, the final pass runs on-device
  over windowed transcript chunks; the note is marked "processed on-device"
  and can be re-polished later when online.
- **BYO API key (optional):** Settings → "Custom model provider" — paste a
  Claude (or other) API key, stored in the macOS Keychain; the final pass
  routes to that provider via the same `LanguageModel` protocol. Default
  remains PCC.

### Note structure

A finished `ReviewNote` contains:

1. **Summary & verdict** — what was presented, outcome (approved / needs
   changes / rejected), key decisions.
2. **Action items** — concrete one-liners, each expandable into an **in-depth
   subsection**: full detail, who raised it, reasoning, short supporting quotes
   from the discussion. Checkable (done/not-done).
3. **Open questions** — unresolved items, attributed, with a resolved flag.

No transcript is stored; supporting quotes inside in-depth sections are the only
verbatim text that persists.

### Data model & storage

SwiftData with a **CloudKit-compatible schema from day one** (no unique
constraints; relationships optional; defaults everywhere):

- `ReviewNote` — title, date, duration, summary, verdict, processing status
- `ActionItem` — one-liner, in-depth detail, attribution, supporting quotes, done flag
- `OpenQuestion` — text, attribution, resolved flag
- `Speaker` — session-scoped label ("You", "Reviewer 1", or a real name heard in-meeting)

- **MVP:** iCloud sync of the user's own notes across their Macs
  (SwiftData + CloudKit, automatic via Apple ID — no account system).
- **Phase 3:** share a note with teammates via CloudKit sharing (`CKShare`) —
  they can view, edit, and check off action items. Apple-platform collaborators
  only. No backend, no sign-up, ever.

### Shortcut, Siri & App Intents

- `StartReviewCaptureIntent` / `StopReviewCaptureIntent` — exposed via App
  Intents. This single investment yields: user-assignable global keyboard
  shortcut, "Hey Siri, start capturing the review", Shortcuts-app automation,
  and Spotlight.
- `GetLastReviewSummaryIntent` — Siri can answer "what were my action items
  from the last review?"

### Review Assistant (phase 2)

An agent over your own reviews — not a chatbot. A query field in the main
window answers questions across the note corpus:

- "Summarize every networking issue from the last month."
- "Which action items are still unresolved?"
- "Which reviewer requests keep recurring?"

**How:** Foundation Models tool calling over SwiftData. The model is given
typed tools — e.g. `searchActionItems(status:dateRange:topic:)`,
`fetchNoteSummaries(since:)`, `listSpeakerComments(speaker:)` — that run
predicates against the local store and return structured results. Simple
lookups run fully on-device; cross-note synthesis (recurring themes, monthly
rollups) routes to PCC via the same `LanguageModel` protocol. Answers cite and
deep-link to source notes. Also exposed as an App Intent so Siri can answer
review questions. Works because notes are typed data, not transcripts — no
embedding index or RAG pipeline needed.

### Markdown export (agent-ready)

Every note exports as a Markdown file deliberately formatted as **context for a
coding agent**: summary, verdict, action items with in-depth subsections and
quotes, open questions. Intended workflow: drop it into Claude Code (or any
agent) — "this was the review; make these changes." This delivers the
review-to-code story in phase 1.

## Permissions & failure handling

- **Mic** — standard prompt on first capture.
- **System audio** — audio-capture entitlement + system audio recording
  permission (Privacy & Security). First-run onboarding walks through both.
  If denied → capture proceeds mic-only with a visible banner.
- Transcription + live extraction are fully on-device — zero-network capable.
  Only the final polish needs network (with on-device fallback).
- **Crash mid-meeting:** in-memory transcript is lost by design; live-extracted
  points are checkpointed to SwiftData as they appear, so everything already
  extracted survives.

## Phasing

| Phase | Scope |
|---|---|
| **1 (MVP)** | Shortcut → listen → live points → final PCC pass → note library; mic+system-audio attribution; iCloud sync of own notes; Markdown export; App Intents/Siri; BYO API key |
| **2** | Review Assistant: tool-calling agent over the note corpus (unresolved items, recurring themes, monthly rollups), on-device + PCC, cited answers |
| **3** | Team sharing via CloudKit `CKShare` (view/edit/check off) |
| **4** | FluidAudio voice diarization → true in-room speaker separation |
| **5** | GitHub connector: per-project repo link; Foundation Models tool calling searches the repo and attaches file/line references to each action item |

## Testing

- Unit tests at pipeline seams: fake audio-segment sources feeding attribution
  and extraction stages; `@Generable` schema round-trips; PCC-unavailable →
  on-device fallback behavior.
- Model-output quality: small fixture set of synthetic review transcripts with
  expected points — evaluated manually, not exact-asserted.
- Review Assistant: fixture corpus of notes with known-answer queries
  (unresolved counts, recurring topics) asserting the tools return correct
  data; phrasing quality checked manually.
- Sync/sharing: exercised on two signed-in machines before phase-3 completion.

## Non-goals

- No iOS/iPadOS companion.
- No audio recording or transcript persistence — ever, in any phase.
- No account system, no self-hosted backend.
- No web viewer for non-Apple collaborators (revisit only if real demand).
