# RevueAI Pipeline Improvements — Design Spec

**Date:** 2026-07-06
**Scope:** Capture/extraction pipeline only — no UI/UX work beyond making new data visible.
**Context:** PCC entitlement is applied for but not yet granted; on-device
`SystemLanguageModel` is the working backend. Everything here must work
on-device today and get strictly better (or become a no-op) when PCC arrives.

## Goals

1. **Robustness for real meetings** — a 30–60 min session must produce a good
   note without overflowing the on-device context window or losing data.
2. **Extraction quality** — persist decisions, refine speaker attribution in
   the final pass, dedup live points.
3. **Test harness** — fakes behind the existing protocol seams plus unit tests
   at every pipeline stage (the spec's testing section, finally built).
4. **Latency & efficiency** — prewarm the model, extract on demand rather than
   on a blind timer.

## Non-goals

- No PCC enablement (blocked on entitlement), no BYO-key executor, no App
  Intents, no iCloud sync, no voice diarization. No UI redesign.

---

## 1. Windowed final pass & robustness

### TranscriptWindower (new)

A pure, stateless utility: takes `[AudioSegment]` and a token budget, returns
`[[AudioSegment]]` windows. Token estimation uses a ~4 characters/token
heuristic. Consecutive windows overlap by 2 segments (a named constant) so
points spanning a window boundary aren't lost. Single-window passthrough when
the transcript fits the budget.

### Backend-aware context budget

`ReviewLanguageModel` gains `var contextTokenBudget: Int`:

- `OnDeviceReviewModel` ≈ 3,000 (leaves headroom for instructions + output)
- `PrivateCloudReviewModel` ≈ 24,000

With PCC's budget most meetings fit one window, so the windowed machinery
collapses to today's single-call path with zero code changes when PCC lands.

### FinalPolisher flow

1. Transcript fits budget → existing single `polish(transcript:livePoints:)`
   call, unchanged.
2. Otherwise **map-reduce**:
   - **Map:** per window, call the existing
     `extractPoints(fromChunk:knownPoints:)` with accumulated known points,
     collecting enriched candidates (with verbatim quotes).
   - **Reduce:** one `polish` call whose transcript input is the formatted
     candidate list + live points, labeled in the prompt as pre-extracted
     points rather than raw transcript. No new protocol method.
3. A failed window is skipped, not fatal; the reduce runs over what succeeded.
   Total failure keeps checkpointed live points and marks the note
   `.processedOnDevice`, as today.

### Live-chunk watermark fix

`RollingTranscript.drainNewSegments()` splits into `peekNewSegments()` +
`commitExtracted(count:)`. `CaptureCoordinator` commits only after
`LiveExtractor` succeeds, so a failed live extraction leaves the chunk queued
for the next cadence tick instead of silently dropping it.

### Known-points cap

The live pass sends only the most recent ~25 one-liners plus a
"(+N earlier points)" marker, bounding live-pass context on long meetings.
The final pass still sees all points.

---

## 2. Extraction quality

### Decision model (new)

`@Model final class Decision` — `id: UUID`, `statement: String`,
`attribution: String`, `order: Int`, optional `note: ReviewNote?` inverse —
mirroring `OpenQuestion`. CloudKit-safe (defaults everywhere, optional
relationship). `ReviewNote` gains a cascading `decisions` relationship and
`sortedDecisions`. Wire-through:

- `LiveExtractor` persists the `DecisionCandidate`s it already receives.
- `PolishedReview` gains `decisions: [DecisionCandidate]`; `FinalPolisher`
  applies them like action items/questions.
- `MarkdownExporter` gains a `## Decisions` section.
- Minimal display in `NoteDetailView` so the feature is verifiable.

### Speaker refinement (final pass only)

`PolishedReview` gains `speakers: [SpeakerCandidate]` (`label: String`,
`isPresenter: Bool`). Polish instructions extended: build a roster of distinct
speakers — real names heard aloud where possible, otherwise "Reviewer 1"/"
Reviewer 2" — and attribute every action item, decision, and question using
labels from that roster. `FinalPolisher.apply` creates `Speaker` records on
the note (the model and relationship already exist, currently unused). The
live pass stays binary (You/Reviewer).

### Shared dedup helper

`FinalPolisher`'s `normalize`/`similar` fuzzy matching moves to a shared
`PointDedup` utility. `LiveExtractor` uses it as a code-level backstop so
near-identical one-liners don't accumulate in the live panel; the model's
known-points instruction remains the first line of defense.

---

## 3. Latency & efficiency

- **Prewarm:** `ReviewLanguageModel` gains `func prewarm()` with a default
  no-op extension. `OnDeviceReviewModel` calls `LanguageModelSession.prewarm()`
  when capture starts so the first live extraction doesn't pay model-load
  latency.
- **Hybrid cadence:** replace the fixed 20s timer with: extract when ≥6 new
  segments have accumulated, or when the interval elapses with ≥1 new segment,
  whichever comes first. Silence produces zero model calls. Thresholds remain
  named constants on `CaptureCoordinator`.

---

## 4. Test harness

New `RevueAITests` unit-test target (first tests in the project).

**Fakes behind existing seams:**

- `FakeTranscriptionService: TranscriptionProviding` — plays a scripted list
  of phrases into the stream; can throw on `start()` to simulate a denied tap.
- `FakeReviewModel: ReviewLanguageModel` — canned `ExtractedPoints` /
  `PolishedReview` responses, injectable failures, records calls and inputs.

**Tests at each seam** (SwiftData tests use an in-memory container):

| Unit | What's asserted |
|---|---|
| `RollingTranscript` | peek/commit watermark semantics; failed extraction leaves segments queued |
| `TranscriptWindower` | budget respected; overlap correct; no lost or duplicated segments; single-window passthrough |
| `LiveExtractor` | checkpointing to SwiftData; dedup backstop; decision persistence |
| `FinalPolisher` | single vs map-reduce path selection by budget; window-failure tolerance; total failure preserves live points; speaker roster application |
| `CaptureCoordinator` | full lifecycle with fakes (start → live points → pause/resume → stop → polished note); mic-only fallback when system stream throws |
| `MarkdownExporter` | fixture note → expected markdown, incl. Decisions section |

**Fixture:** one synthetic review transcript with known expected points,
driving a coordinator end-to-end test against the fake model.

---

## Build order

Each step leaves the app building and working:

1. Test target + fakes + tests covering existing behavior (baseline safety net)
2. Watermark fix + known-points cap
3. `TranscriptWindower` + `FinalPolisher` map-reduce
4. `Decision` model end-to-end (live pass → polish → export → minimal display)
5. Speaker refinement in the final pass
6. Prewarm + hybrid cadence
7. Shared `PointDedup` helper

## Error handling summary

- Live extraction failure → chunk stays queued (watermark uncommitted); error
  surfaced via existing `errorMessage`.
- Window failure in map phase → window skipped, reduce proceeds.
- Full polish failure → live points preserved, note `.processedOnDevice`
  (unchanged from today).
- System-audio tap failure → mic-only with visible error (unchanged).

## Privacy invariant (unchanged)

No new persistence paths for audio or transcript. Windows are views over the
in-memory `RollingTranscript`; everything is discarded on `clear()` as today.
