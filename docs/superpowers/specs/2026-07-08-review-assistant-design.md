# Review Assistant — Design Spec

**Date:** 2026-07-08
**Status:** Approved (brainstorm 2026-07-08)
**Scope:** Phase 2 of the original product spec: a tool-calling agent that
answers questions across the note corpus, in an inspector panel and via Siri.

## What & why

Notes accumulate; answers shouldn't require re-reading them. The assistant
answers questions like "which action items are still unresolved?", "what did
we decide about the upload path?", or "summarize every networking issue from
the last month" — by querying the typed SwiftData corpus with tools, never by
reading transcripts (none exist, by design). No embeddings or RAG: the data
is already structured.

## Architecture: tool calling with deterministic citations

One `LanguageModelSession(tools:instructions:)` on the on-device
`SystemLanguageModel` per conversation. The model decides which tools to
call; tools run real SwiftData fetches; the model phrases the final answer as
plain text.

**Citations never come from the model.** Every tool records the note IDs its
results came from into a per-question `SourceLog`; the UI builds clickable
source chips from that log. A small on-device model cannot reliably emit
identifiers, so it is never asked to.

### Components

- **`SourceLog`** (`@MainActor` final class): `record(_ note: ReviewNote)`,
  `takeSnapshot() -> [SourceRef]` (dedup by note id, capped at 8), `reset()`.
  `SourceRef` = note id + title, `Identifiable`/`Equatable`.
- **`AssistantTools`** (one file): four structs conforming to Foundation
  Models' `Tool`, each with `@Generable` arguments and a compact text output.
  All hold `(ModelContext, SourceLog)` and run on the main actor:
  - `SearchActionItemsTool` — `status` (open/done/any), optional `tag`,
    optional `matching` substring (one-liner, case-insensitive), optional
    `sinceDays`. Output lines: `– <one-liner> [<priority>] (<note title>,
    <date>)`.
  - `ListOpenQuestionsTool` — `unresolvedOnly: Bool`.
  - `FetchNoteSummariesTool` — optional `matching` (title/summary), optional
    `sinceDays`. Output: `<title> (<date>, <verdict>): <summary>`.
  - `ListDecisionsTool` — optional `matching`, optional `sinceDays`.
  Empty result sets return an explicit "no matches" line so the model doesn't
  invent content. Outputs are truncated to the top 20 matches, newest first.
- **`AssistantAnswering`** (protocol seam, mirrors `ReviewLanguageModel`'s
  role): `var isAvailable: Bool`, `func startConversation(tools:) ->
  AssistantConversation`, where `AssistantConversation` exposes
  `func ask(_ question: String) async throws -> String`. Production
  implementation wraps `LanguageModelSession` (created once per conversation
  so follow-ups carry context); tests use a fake returning canned answers.
- **`ReviewAssistant`** (`@MainActor @Observable`): the panel's model.
  `struct Exchange: Identifiable { question, answer, sources: [SourceRef],
  failed: Bool }`; `private(set) var exchanges: [Exchange]`;
  `private(set) var isThinking: Bool`;
  `func ask(_ question: String, context: ModelContext) async` — resets the
  source log, appends a pending exchange, awaits the conversation, snapshots
  sources into the exchange; `func clear()` drops the thread and the session.
  The thread is session-only — never persisted.

### Instructions prompt

The session instructions tell the model: it answers questions about the
user's review notes; it MUST use the provided tools to look anything up; it
answers concisely from tool results only and says so when a search returns
nothing; it never fabricates notes, items, or dates.

## Surfaces

### Inspector panel

The right-hand inspector becomes a two-mode slot (`enum InspectorPane { case
live, assistant }`): the existing waveform toolbar button shows Live, a new
sparkles toolbar button shows Assistant; opening one closes the other, and a
capture starting still auto-opens Live. The assistant panel: query field
pinned at top (submit on return, disabled while `isThinking`), exchanges
scrolling below (question in secondary text, answer in body text,
progress indicator while thinking), and a source-chip row under each answer —
clicking a chip selects that note in the shell (same jump used by the
calendar's note badges). A Clear button empties the thread. If the model is
unavailable, the panel shows the existing Apple-Intelligence-off banner
instead of the query field.

### Siri App Intent

`AskRevueAIIntent` (App Intents): one `question` parameter; runs the same
tools + a one-shot conversation headlessly against the shared model
container; returns `ProvidesDialog` with the answer text, appending "From: "
+ up to three source note titles when sources exist. Registered in an
`AppShortcutsProvider` with the phrase "Ask ${applicationName} …". The intent
opens no UI.

## Error handling

- Model unavailable → panel banner; intent returns an "Apple Intelligence is
  off" dialog.
- A throwing ask → the exchange is marked `failed` with a short retryable
  message; the thread and session survive.
- Tool fetch failures degrade to the "no matches" line (fetches are `try?`),
  so a storage hiccup reads as an empty result, not a crash.
- Guardrail/refusal errors from the session read as a failed exchange.

## Testing

- **Tools against a fixture corpus** (the original spec's plan): an in-memory
  context seeded with notes/items/questions/decisions across dates, tags,
  and statuses; call each tool's `call(arguments:)` directly and assert the
  returned text contains/omits the right entries and that `SourceLog`
  captured the right notes.
- **`ReviewAssistant`** with a fake `AssistantAnswering`: exchanges append in
  order, `isThinking` toggles, sources snapshot per exchange, failures mark
  the exchange without killing the thread, `clear()` resets.
- **`SourceLog`**: dedup, cap, snapshot/reset semantics.
- Answer phrasing quality: manual, per the original spec.

## Non-goals

- No persistence of conversations.
- No PCC routing yet (on-device only; the seam allows it later).
- No cross-note synthesis beyond what tool outputs + the model's phrasing
  give; no embeddings.
- No assistant access to transcripts (none are stored — by design).
