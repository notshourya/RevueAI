# Destinations Platform: Custom Workflow Bridges + GitHub/Jira/Slack Presets

**Status:** Approved 2026-07-10

## Goal

Let any user push curated review output into *their* workflow — a GitHub
issue, a Jira ticket, a Slack message, or any internal tool with an HTTP
endpoint — through one user-configurable "destination" system. Popular
trackers ship as presets; everything else is a custom destination. This is
stage one of the platform strategy: open edges instead of walled
integrations.

## Product decisions (made during brainstorming)

1. **Custom core, preset skins.** GitHub, Jira, and Slack are factory-made
   instances of the same custom-destination machinery — no special-case
   send paths.
2. **Two granularities.** Item-level destinations (one action item → one
   issue) and note-level destinations (whole-note digest → chat/wiki/
   webhook).
3. **Auth = tokens in Keychain (v1).** User pastes a GitHub fine-grained
   PAT, Jira API token, Slack webhook URL/bot token, or arbitrary header
   value. Stored in the macOS Keychain keyed by destination ID. No OAuth
   apps, no RevueAI accounts — ever, for the local tier.
4. **Manual sends + small auto-rules.** Explicit "File to…"/"Send to…"
   actions, plus per-destination toggles (no rule engine): auto-send note
   digest on polish completion; auto-file items at or above a chosen
   priority on polish completion.
5. **No accounts.** Monetization later via StoreKit (free capture, Pro
   platform features); accounts only if/when server-backed team features
   exist. Not part of this spec beyond the constraint: nothing here may
   require an account or our own server.

## Architecture

```
ActionItem / ReviewNote
        │  (render)
   TemplateRenderer ── {{vars}}, {{#items}} loops, JSON-aware escaping
        │
   DestinationSender ── builds URLRequest, attaches Keychain auth,
        │               sends via injectable Transport, parses remote URL
        ▼
   ExportRecord (SwiftData) ── what/where/when/status/remoteURL
```

- `Destination` (SwiftData `@Model`): `id`, `name`, `kind` (`.item` |
  `.note`), `preset` (`.github` | `.jira` | `.slack` | `.custom`),
  `urlTemplate`, `httpMethod`, `headers: [String: String]` (non-secret),
  `config: [String: String]` (preset fields like repo/site/project key,
  templated as `{{config.*}}`), `bodyTemplate`, `authStyle` (`.bearerToken` | `.basicEmailToken` |
  `.headerValue` | `.none` — webhook URLs carry their secret in the URL),
  auto-rule fields (`autoSendOnPolish: Bool`,
  `autoFileMinPriorityRaw: String?`), `order`.
- **Secrets in Keychain only**, service `"RevueAI.destination"`, account =
  destination UUID string. Jira needs email + token → stored as one
  Keychain item (`email:token`), split by the sender. Deleting a
  destination deletes its Keychain item.
- `TemplateRenderer`: pure function `(template, context) -> String`.
  Context built from a note or item. JSON mode escapes interpolated values
  (quotes, newlines, backslashes) so templates can be JSON bodies.
- `Transport` protocol (`send(URLRequest) async throws -> (Data,
  HTTPURLResponse)`) with a `URLSessionTransport` and a test mock.
- `DestinationSender`: `send(item:to:context:)` / `send(note:to:context:)`.
  Renders URL + body templates, attaches auth from Keychain, sends,
  extracts the created resource URL via the preset's response key path
  (`html_url` for GitHub, `key` → browse URL for Jira, none for Slack
  webhooks/custom), writes an `ExportRecord`, returns it.
- `ExportRecord` (SwiftData `@Model`): `id`, `date`, `destinationName`,
  `destinationID`, `remoteURL: String?`, `succeeded: Bool`,
  `statusCode: Int`, `subjectKind` (`.item`/`.note`), relationships:
  optional `item: ActionItem?`, optional `note: ReviewNote?` (inverses:
  `ActionItem.exportRecords`, `ReviewNote.exportRecords`; optional arrays
  for CloudKit).

## Presets

A preset is a factory returning a pre-filled `Destination` plus the list
of fields the user must supply:

| Preset | User supplies | Transport | Template highlights | Response |
|--------|--------------|-----------|---------------------|----------|
| GitHub (item) | owner/repo, fine-grained PAT | `POST https://api.github.com/repos/{{config.repo}}/issues`, bearer | title = `{{oneLiner}}`; body = rationale + detail + quotes + tags as labels-ready list; `labels` from tags | `html_url` |
| Jira (item) | site URL, project key, email + API token | `POST {{config.site}}/rest/api/3/issue`, basic (email:token) | `fields.summary` = `{{oneLiner}}`; ADF description from rationale/detail; priority mapped blocker→Highest, major→High, minor→Medium, nit→Low | `key` → `{{config.site}}/browse/KEY` |
| Slack (note) | incoming webhook URL | `POST` to webhook, no extra auth | Block Kit JSON: header = `{{title}}`, verdict + date context, summary section, `{{#items}}` bulleted open items, decisions list | none (2xx = sent) |
| Custom (item or note) | everything: URL, method, headers, auth style + secret, body template | as configured | starter template provided per kind | none (2xx = sent) |

Preset config values (repo, site, project key) are stored in the
destination's `headers`-adjacent config map (`config: [String: String]`),
referenced in templates as `{{config.*}}` — so presets stay ordinary
destinations with editable templates.

## Template language

Mustache-subset, implemented in ~100 lines, no dependency:

- `{{var}}` — substitution from the context.
- `{{#items}} … {{/items}}` — loop over open action items (note context
  only); inside the loop, item variables resolve per item.
- Note context: `title`, `summary`, `date`, `verdict`, `durationMinutes`,
  `openCount`, `doneCount`, `decisions` (pre-joined bulleted string),
  `config.*`.
- Item context: `oneLiner`, `rationale`, `inDepthDetail`, `attribution`,
  `priority`, `category`, `tags` (comma-joined), `tagsJSONArray`,
  `noteTitle`, `noteDate`, `config.*`.
- Rendering modes: `.plain` and `.json` (values escaped for embedding
  inside JSON string literals). Unknown variables render empty.

## Auto-rules

Evaluated in one place — when a note's polish completes (the existing
final-polish completion point):

- For every note-kind destination with `autoSendOnPolish`: send the digest.
- For every item-kind destination with `autoFileMinPriority`: send each of
  the note's items with priority ≥ threshold that has **no prior
  successful ExportRecord for that destination** (no duplicate filing).

Failures are non-blocking: the record is written with `succeeded: false`
and the note shows a quiet failure chip; retry is manual. No background
retry queue in v1.

## UI (native, glass-styled, no new windows)

- **Settings → Destinations**: list of configured destinations with
  preset icons; add flow = preset picker sheet → minimal field form
  (only what that preset needs) → optional template editing (monospaced
  TextEditor) → "Send test" button that posts a sample payload and shows
  the result inline. Edit and delete (delete also removes the Keychain
  secret).
- **Item popover + board row context menu**: "File to <destination>…"
  submenu listing item-kind destinations; after success the popover
  footer shows a chip linking to `remoteURL`. Re-filing to a destination
  that already has a successful record asks for confirmation
  ("Already filed — file again?").
- **Export pulldown (toolbar)**: "Send to <destination>" entries for
  note-kind destinations under the existing Copy/Share section.
- **Sent state**: items with ≥1 successful export show a small
  arrow-up-right chip in the detail popover footer; the note header stat
  chips gain nothing (keep clean) — export history lives in the popover
  and export menu ("View sent history" sheet listing ExportRecords with
  links and retry for failures).

## Sandbox / entitlements

Add `com.apple.security.network.client` to the app target (first outbound
network use in the app). Keychain access needs no extra entitlement for
the default keychain.

## Error handling

- Missing/removed Keychain secret at send time → alert prompting to
  re-enter the token in Settings (send aborted, no record written).
- Non-2xx → `ExportRecord(succeeded: false, statusCode:)`; the UI surface
  that initiated the send shows the status and response snippet.
- Template rendering never throws: unknown variables → empty string;
  malformed loop syntax → rendered literally (visible in "Send test").
- Auto-rule sends never block or alert; failures surface as the note's
  failure chip.

## Testing (Swift Testing, mock transport, no live network)

- TemplateRenderer: substitution, loops, JSON escaping, unknown vars,
  malformed blocks.
- Preset factories: each produces the documented transport/templates and
  required-field lists.
- DestinationSender: request construction (URL, method, headers, auth
  styles), response URL extraction per preset, ExportRecord written on
  success and failure, duplicate detection.
- Auto-rules: predicate selects the right items (priority threshold, no
  prior success), digest fires only when toggled.
- Keychain wrapper: round-trip store/read/delete (against the real local
  keychain, tagged to allow CI skip if needed).

## Out of scope (explicitly)

- OAuth flows (later polish; PKCE, still account-free).
- Status pull-back / two-way sync.
- Rule engine beyond the two toggles.
- StoreKit/Pro gating (separate effort; nothing here may assume it).
- MCP server, Shortcuts trigger surface (stage two of the platform).
