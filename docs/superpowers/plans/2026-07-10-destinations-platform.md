# Destinations Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One user-configurable "destination" system that pushes curated review output to any HTTP endpoint, with GitHub/Jira/Slack as presets, auto-rules, a Settings editor, and a sidebar destinations dock with drag-to-file.

**Architecture:** `Destination` + `ExportRecord` SwiftData models with secrets in the Keychain; a pure mustache-subset `TemplateRenderer`; a `DestinationSender` over an injectable `Transport`; presets as factory-made destinations; an `AutoRuleEngine` hooked to polish completion; SwiftUI surfaces (Settings section, dock strip, item/note send menus).

**Tech Stack:** SwiftUI (macOS 27), SwiftData, Security.framework (Keychain), URLSession, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-07-10-destinations-platform-design.md`

## Global Constraints

- Build/test with plain `xcodebuild` (system-selected Xcode 27 beta; no DEVELOPER_DIR).
- Full test command: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' 2>&1 | grep -E "error:|Test run|TEST (SUCCEEDED|FAILED)"` — never `-quiet`.
- Gate every commit: tests to a log, then `grep -q "TEST SUCCEEDED" $LOG && git add <specific files> && git commit …`.
- NEVER `pkill` the app; NEVER `git add -A` (parallel session owns `MyApp/RevueAIApp.swift`, `MyApp/Shaders.metal`, `MyApp/Capture/AudioLevelMonitor.swift`, `MyApp/Views/Orb*.swift`, `MyApp/Views/SiriOrbView.swift`, `test_script.swift`). Stage by exact path.
- Re-read collision-prone files immediately before editing (`ItemPopup.swift`, `ActionItemBoard.swift`, `LibraryView.swift`, `RootShellView.swift`, `SettingsView.swift`).
- New `.swift` files under `MyApp/` and `RevueAITests/` are picked up automatically (file-system-synchronized groups).
- Secrets NEVER go into SwiftData/CloudKit — Keychain only, service `"RevueAI.destination"`, account = destination UUID string.
- No accounts, no our-own-server assumptions anywhere.
- Tests use the mock transport — no live network calls in tests.
- Design language: rounded fonts, small-caps kerned headers, `.glassEffect` surfaces, system accent only.

---

### Task 1: Models, schema, Keychain secrets

**Files:**
- Create: `MyApp/Destinations/DestinationModels.swift`
- Create: `MyApp/Destinations/DestinationSecrets.swift`
- Modify: `MyApp/SharedModel.swift` (schema list)
- Modify: `MyApp/Models/ActionItem.swift` (add `exportRecords`)
- Modify: `MyApp/Models/ReviewNote.swift` (add `exportRecords`)
- Modify: `RevueAITests/Support/TestSupport.swift` (schema list)
- Test: `RevueAITests/DestinationModelsTests.swift`

**Interfaces:**
- Consumes: existing `ActionPriority` (`sortRank: Int`, lower = more urgent).
- Produces: `DestinationKind` (`.item`/`.note`), `DestinationPreset` (`.github`/`.jira`/`.slack`/`.custom`), `DestinationAuthStyle` (`.bearerToken`/`.basicEmailToken`/`.headerValue`/`.urlSecret`/`.none`), `Destination` (@Model, fields below), `ExportSubjectKind` (`.item`/`.note`), `ExportRecord` (@Model), `DestinationSecrets.store(_:for:)`, `.read(for:) -> String?`, `.delete(for:)`, `ActionItem.exportRecords: [ExportRecord]?`, `ReviewNote.exportRecords: [ExportRecord]?`.

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/DestinationModelsTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import RevueAI

struct DestinationModelsTests {
    @Test func destinationRoundTripsThroughStore() throws {
        let context = try makeInMemoryContext()
        let destination = Destination(
            name: "Team GitHub", kind: .item, preset: .github,
            urlTemplate: "https://api.github.com/repos/{{config.repo}}/issues",
            bodyTemplate: "{}", authStyle: .bearerToken,
            config: ["repo": "acme/api"]
        )
        context.insert(destination)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Destination>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.kind == .item)
        #expect(fetched.first?.preset == .github)
        #expect(fetched.first?.authStyle == .bearerToken)
        #expect(fetched.first?.config["repo"] == "acme/api")
    }

    @Test func exportRecordLinksToItemAndNote() throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "API review")
        let item = ActionItem(oneLiner: "Fix pagination")
        item.note = note
        context.insert(note)
        context.insert(item)

        let record = ExportRecord(destinationName: "Team GitHub",
                                  destinationID: UUID(),
                                  subjectKind: .item)
        record.item = item
        record.note = note
        record.succeeded = true
        record.remoteURL = "https://github.com/acme/api/issues/7"
        context.insert(record)
        try context.save()

        #expect(item.exportRecords?.count == 1)
        #expect(note.exportRecords?.count == 1)
        #expect(item.exportRecords?.first?.remoteURL?.contains("issues/7") == true)
    }

    @Test func keychainSecretRoundTrip() {
        let id = UUID()
        DestinationSecrets.store("ghp_secret123", for: id)
        #expect(DestinationSecrets.read(for: id) == "ghp_secret123")
        DestinationSecrets.store("ghp_rotated", for: id)
        #expect(DestinationSecrets.read(for: id) == "ghp_rotated")
        DestinationSecrets.delete(for: id)
        #expect(DestinationSecrets.read(for: id) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
LOG=/tmp/dest-t1a.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' \
  -only-testing:RevueAITests/DestinationModelsTests > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
```

Expected: build errors — `cannot find 'Destination' in scope`, `cannot find 'DestinationSecrets' in scope`.

- [ ] **Step 3: Create the models**

Create `MyApp/Destinations/DestinationModels.swift`:

```swift
import Foundation
import SwiftData

/// Whether a destination receives single action items or whole-note digests.
enum DestinationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case item, note
    var id: String { rawValue }
}

/// Built-in preset identity; presets are ordinary destinations with
/// factory-filled transport and templates.
enum DestinationPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case github, jira, slack, custom
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .jira: return "Jira"
        case .slack: return "Slack"
        case .custom: return "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .jira: return "checklist"
        case .slack: return "bubble.left.and.bubble.right"
        case .custom: return "network"
        }
    }
}

/// How the Keychain secret is attached to the request.
enum DestinationAuthStyle: String, Codable, CaseIterable, Sendable {
    /// `Authorization: Bearer <secret>`
    case bearerToken
    /// Secret stored as "email:token" → `Authorization: Basic <base64>`
    case basicEmailToken
    /// Secret placed verbatim in the header named by `config["authHeader"]`
    /// (defaults to `Authorization`).
    case headerValue
    /// The secret IS the request URL (e.g. Slack incoming webhooks);
    /// `urlTemplate` is ignored.
    case urlSecret
    case none
}

/// A user-configured place review output can be sent. Presets (GitHub,
/// Jira, Slack) are factory-made instances of this same model. Secrets are
/// never stored here — Keychain only (see DestinationSecrets).
@Model
final class Destination {
    var id: UUID = UUID()
    var name: String = ""
    private var kindRaw: String = DestinationKind.item.rawValue
    private var presetRaw: String = DestinationPreset.custom.rawValue
    var urlTemplate: String = ""
    var httpMethod: String = "POST"
    /// Non-secret extra headers.
    var headers: [String: String] = [:]
    /// Preset fields (repo, site, project key…), templated as {{config.*}}.
    var config: [String: String] = [:]
    var bodyTemplate: String = ""
    private var authStyleRaw: String = DestinationAuthStyle.none.rawValue
    /// Auto-rule: send the note digest when polish completes (note-kind).
    var autoSendOnPolish: Bool = false
    /// Auto-rule: file items at/above this priority on polish (item-kind).
    private var autoFileMinPriorityRaw: String?
    var order: Int = 0

    var kind: DestinationKind {
        get { DestinationKind(rawValue: kindRaw) ?? .item }
        set { kindRaw = newValue.rawValue }
    }
    var preset: DestinationPreset {
        get { DestinationPreset(rawValue: presetRaw) ?? .custom }
        set { presetRaw = newValue.rawValue }
    }
    var authStyle: DestinationAuthStyle {
        get { DestinationAuthStyle(rawValue: authStyleRaw) ?? .none }
        set { authStyleRaw = newValue.rawValue }
    }
    var autoFileMinPriority: ActionPriority? {
        get { autoFileMinPriorityRaw.flatMap(ActionPriority.init(rawValue:)) }
        set { autoFileMinPriorityRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        kind: DestinationKind = .item,
        preset: DestinationPreset = .custom,
        urlTemplate: String = "",
        httpMethod: String = "POST",
        headers: [String: String] = [:],
        bodyTemplate: String = "",
        authStyle: DestinationAuthStyle = .none,
        config: [String: String] = [:],
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.presetRaw = preset.rawValue
        self.urlTemplate = urlTemplate
        self.httpMethod = httpMethod
        self.headers = headers
        self.bodyTemplate = bodyTemplate
        self.authStyleRaw = authStyle.rawValue
        self.config = config
        self.order = order
    }
}

enum ExportSubjectKind: String, Codable, Sendable {
    case item, note
}

/// One send attempt: what went where, when, and how it ended.
@Model
final class ExportRecord {
    var id: UUID = UUID()
    var date: Date = Date.now
    var destinationName: String = ""
    var destinationID: UUID = UUID()
    var remoteURL: String?
    var succeeded: Bool = false
    var statusCode: Int = 0
    private var subjectKindRaw: String = ExportSubjectKind.item.rawValue
    /// Inverses: ActionItem.exportRecords / ReviewNote.exportRecords.
    var item: ActionItem?
    var note: ReviewNote?

    var subjectKind: ExportSubjectKind {
        get { ExportSubjectKind(rawValue: subjectKindRaw) ?? .item }
        set { subjectKindRaw = newValue.rawValue }
    }

    init(destinationName: String, destinationID: UUID, subjectKind: ExportSubjectKind) {
        self.destinationName = destinationName
        self.destinationID = destinationID
        self.subjectKindRaw = subjectKind.rawValue
    }
}
```

- [ ] **Step 4: Create the Keychain wrapper**

Create `MyApp/Destinations/DestinationSecrets.swift`:

```swift
import Foundation
import Security

/// Keychain storage for destination secrets (tokens, webhook URLs).
/// Service is fixed; the account is the destination's UUID string, so
/// deleting a destination can delete exactly its secret.
enum DestinationSecrets {
    static let service = "RevueAI.destination"

    static func store(_ secret: String, for id: UUID) {
        let account = id.uuidString
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func read(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 5: Register the models and add inverse relationships**

In `MyApp/SharedModel.swift`, extend the schema list:

```swift
        let schema = Schema([
            ReviewNote.self,
            ActionItem.self,
            OpenQuestion.self,
            Decision.self,
            Speaker.self,
            PlannedCapture.self,
            MeetingSnapshot.self,
            Destination.self,
            ExportRecord.self,
        ])
```

Apply the identical two-line addition to the schema in
`RevueAITests/Support/TestSupport.swift` (`makeInMemoryContainer`).

In `MyApp/Models/ActionItem.swift`, below `var note: ReviewNote?` add:

```swift
    /// Sends of this item to destinations. Optional array for CloudKit.
    var exportRecords: [ExportRecord]? = []
```

In `MyApp/Models/ReviewNote.swift`, below `var meetingSnapshot: MeetingSnapshot?` add:

```swift
    /// Sends of this note (digests and item files). Optional for CloudKit.
    var exportRecords: [ExportRecord]? = []
```

- [ ] **Step 6: Run to verify pass**

Same command as Step 2. Expected: `TEST SUCCEEDED`.

- [ ] **Step 7: Full suite + commit**

```bash
LOG=/tmp/dest-t1b.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
grep -q "TEST SUCCEEDED" $LOG \
  && git add MyApp/Destinations/DestinationModels.swift MyApp/Destinations/DestinationSecrets.swift \
             MyApp/SharedModel.swift MyApp/Models/ActionItem.swift MyApp/Models/ReviewNote.swift \
             RevueAITests/Support/TestSupport.swift RevueAITests/DestinationModelsTests.swift \
  && git commit -m "feat: destination + export record models, keychain secret store"
```

---

### Task 2: Template renderer + contexts

**Files:**
- Create: `MyApp/Destinations/TemplateRenderer.swift`
- Test: `RevueAITests/TemplateRendererTests.swift`

**Interfaces:**
- Consumes: `ReviewNote`, `ActionItem` (existing fields), `ActionPriority`.
- Produces: `TemplateMode` (`.plain`/`.json`), `TemplateRenderer.render(_ template: String, context: [String: String], items: [[String: String]], mode: TemplateMode) -> String`, `TemplateContextBuilder.context(for note: ReviewNote, config: [String: String]) -> [String: String]`, `.itemContexts(for note: ReviewNote) -> [[String: String]]`, `.context(for item: ActionItem, config: [String: String]) -> [String: String]` (includes `jiraPriority` and `tagsJSONArray`).

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/TemplateRendererTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct TemplateRendererTests {
    @Test func substitutesVariables() {
        let out = TemplateRenderer.render("Hello {{name}}!", context: ["name": "Ada"],
                                          items: [], mode: .plain)
        #expect(out == "Hello Ada!")
    }

    @Test func unknownVariablesRenderEmpty() {
        let out = TemplateRenderer.render("[{{missing}}]", context: [:], items: [], mode: .plain)
        #expect(out == "[]")
    }

    @Test func jsonModeEscapesValues() {
        let out = TemplateRenderer.render(#"{"t": "{{text}}"}"#,
                                          context: ["text": "a \"quote\"\nline2\\end"],
                                          items: [], mode: .json)
        #expect(out == #"{"t": "a \"quote\"\nline2\\end"}"#)
        let data = out.data(using: .utf8)!
        #expect((try? JSONSerialization.jsonObject(with: data)) != nil)
    }

    @Test func itemsLoopRepeatsBlock() {
        let out = TemplateRenderer.render(
            "Items:\n{{#items}}- {{oneLiner}} ({{priority}})\n{{/items}}done",
            context: [:],
            items: [["oneLiner": "Fix A", "priority": "Blocker"],
                    ["oneLiner": "Fix B", "priority": "Nit"]],
            mode: .plain
        )
        #expect(out == "Items:\n- Fix A (Blocker)\n- Fix B (Nit)\ndone")
    }

    @Test func malformedLoopRendersLiterally() {
        let template = "{{#items}} never closed"
        let out = TemplateRenderer.render(template, context: [:], items: [], mode: .plain)
        #expect(out == template)
    }

    @Test func noteContextCarriesCountsAndConfig() throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "API review")
        note.summary = "Went well."
        note.verdict = .approved
        let open = ActionItem(oneLiner: "Fix pagination", priority: .major)
        open.note = note
        let done = ActionItem(oneLiner: "Done thing", isDone: true)
        done.note = note
        context.insert(note); context.insert(open); context.insert(done)

        let vars = TemplateContextBuilder.context(for: note, config: ["repo": "acme/api"])
        #expect(vars["title"] == "API review")
        #expect(vars["openCount"] == "1")
        #expect(vars["doneCount"] == "1")
        #expect(vars["config.repo"] == "acme/api")

        let items = TemplateContextBuilder.itemContexts(for: note)
        #expect(items.count == 1)
        #expect(items.first?["oneLiner"] == "Fix pagination")
    }

    @Test func itemContextMapsJiraPriorityAndTags() throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "API review")
        let item = ActionItem(oneLiner: "Fix it", priority: .blocker, tags: ["perf", "api"])
        item.note = note
        context.insert(note); context.insert(item)

        let vars = TemplateContextBuilder.context(for: item, config: [:])
        #expect(vars["jiraPriority"] == "Highest")
        #expect(vars["tags"] == "perf, api")
        #expect(vars["tagsJSONArray"] == #""perf", "api""#)
        #expect(vars["noteTitle"] == "API review")
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
LOG=/tmp/dest-t2a.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' \
  -only-testing:RevueAITests/TemplateRendererTests > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
```

Expected: build errors — `cannot find 'TemplateRenderer' in scope`.

- [ ] **Step 3: Implement**

Create `MyApp/Destinations/TemplateRenderer.swift`:

```swift
import Foundation

/// Rendering mode: `.json` escapes substituted values so templates can be
/// JSON bodies with interpolations inside string literals.
enum TemplateMode {
    case plain, json
}

/// Mustache-subset renderer: `{{var}}` substitution and a single
/// `{{#items}}…{{/items}}` loop. Unknown variables render empty; a loop
/// without its closing tag renders literally (visible in "Send test").
enum TemplateRenderer {
    private static let loopOpen = "{{#items}}"
    private static let loopClose = "{{/items}}"

    static func render(_ template: String,
                       context: [String: String],
                       items: [[String: String]] = [],
                       mode: TemplateMode) -> String {
        var text = template
        if let open = text.range(of: loopOpen) {
            if let close = text.range(of: loopClose, range: open.upperBound..<text.endIndex) {
                let block = String(text[open.upperBound..<close.lowerBound])
                let rendered = items.map { item in
                    substitute(block, context: context.merging(item) { $1 }, mode: mode)
                }.joined()
                text.replaceSubrange(open.lowerBound..<close.upperBound, with: rendered)
            }
            // No closing tag: leave the template untouched past this point —
            // substitution below still runs so partial output is inspectable.
        }
        return substitute(text, context: context, mode: mode)
    }

    private static func substitute(_ text: String,
                                   context: [String: String],
                                   mode: TemplateMode) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: "{{") {
            out += rest[..<open.lowerBound]
            guard let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) else {
                out += rest[open.lowerBound...]
                return out
            }
            let key = rest[open.upperBound..<close.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            // Loop tags that reach here (e.g. dangling close) render literally.
            if key.hasPrefix("#") || key.hasPrefix("/") {
                out += rest[open.lowerBound..<close.upperBound]
            } else {
                let value = context[key] ?? ""
                out += mode == .json ? jsonEscape(value) : value
            }
            rest = rest[close.upperBound...]
        }
        out += rest
        return out
    }

    static func jsonEscape(_ value: String) -> String {
        var escaped = ""
        for character in value.unicodeScalars {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default:
                if character.value < 0x20 {
                    escaped += String(format: "\\u%04x", character.value)
                } else {
                    escaped.unicodeScalars.append(character)
                }
            }
        }
        return escaped
    }
}

/// Builds the variable dictionaries the renderer consumes.
enum TemplateContextBuilder {
    static func context(for note: ReviewNote, config: [String: String]) -> [String: String] {
        let open = note.sortedActionItems.filter { !$0.isDone }
        let done = note.sortedActionItems.count - open.count
        var vars: [String: String] = [
            "title": note.title,
            "summary": note.summary,
            "date": note.date.formatted(date: .abbreviated, time: .shortened),
            "verdict": note.verdict.displayName,
            "durationMinutes": String(Int(note.durationSeconds / 60)),
            "openCount": String(open.count),
            "doneCount": String(done),
            "decisions": note.sortedDecisions.map { "• \($0.statement)" }.joined(separator: "\n"),
        ]
        for (key, value) in config { vars["config.\(key)"] = value }
        return vars
    }

    /// Per-item variable sets for `{{#items}}` loops — open items only.
    static func itemContexts(for note: ReviewNote) -> [[String: String]] {
        note.sortedActionItems.filter { !$0.isDone }.map(itemVariables)
    }

    static func context(for item: ActionItem, config: [String: String]) -> [String: String] {
        var vars = itemVariables(item)
        vars["noteTitle"] = item.note?.title ?? ""
        vars["noteDate"] = item.note?.date.formatted(date: .abbreviated, time: .omitted) ?? ""
        for (key, value) in config { vars["config.\(key)"] = value }
        return vars
    }

    private static func itemVariables(_ item: ActionItem) -> [String: String] {
        [
            "oneLiner": item.oneLiner,
            "rationale": item.rationale,
            "inDepthDetail": item.inDepthDetail,
            "attribution": item.attribution,
            "priority": item.priority.displayName,
            "category": item.category.displayName,
            "tags": item.tags.joined(separator: ", "),
            "tagsJSONArray": item.tags
                .map { "\"\(TemplateRenderer.jsonEscape($0))\"" }
                .joined(separator: ", "),
            "jiraPriority": jiraPriority(item.priority),
            "noteTitle": item.note?.title ?? "",
            "noteDate": item.note?.date.formatted(date: .abbreviated, time: .omitted) ?? "",
        ]
    }

    private static func jiraPriority(_ priority: ActionPriority) -> String {
        switch priority {
        case .blocker: return "Highest"
        case .major: return "High"
        case .minor: return "Medium"
        case .nit: return "Low"
        }
    }
}
```

Note: `ReviewVerdict.displayName` already exists (used by `VerdictBadge`).

- [ ] **Step 4: Run to verify pass**

Same command as Step 2. Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add MyApp/Destinations/TemplateRenderer.swift RevueAITests/TemplateRendererTests.swift
git commit -m "feat: mustache-subset template renderer with note/item contexts"
```

---

### Task 3: Preset factories

**Files:**
- Create: `MyApp/Destinations/DestinationPresets.swift`
- Test: `RevueAITests/DestinationPresetsTests.swift`

**Interfaces:**
- Consumes: `Destination`, `DestinationKind`, `DestinationPreset`, `DestinationAuthStyle` (Task 1).
- Produces: `PresetField` (`key`, `label`, `isSecret`, `placeholder`), `DestinationPresetFactory.fields(for:kind:) -> [PresetField]`, `.make(preset:kind:name:config:) -> Destination`, `.remoteURL(preset:responseData:config:) -> String?`, `.starterTemplate(for kind:) -> String`.

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/DestinationPresetsTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct DestinationPresetsTests {
    @Test func githubPresetShape() {
        let destination = DestinationPresetFactory.make(
            preset: .github, kind: .item, name: "GH", config: ["repo": "acme/api"])
        #expect(destination.urlTemplate == "https://api.github.com/repos/{{config.repo}}/issues")
        #expect(destination.authStyle == .bearerToken)
        #expect(destination.httpMethod == "POST")
        #expect(destination.bodyTemplate.contains("{{oneLiner}}"))
        #expect(destination.headers["Accept"] == "application/vnd.github+json")
    }

    @Test func jiraPresetShape() {
        let destination = DestinationPresetFactory.make(
            preset: .jira, kind: .item, name: "Jira",
            config: ["site": "https://acme.atlassian.net", "project": "API"])
        #expect(destination.urlTemplate == "{{config.site}}/rest/api/3/issue")
        #expect(destination.authStyle == .basicEmailToken)
        #expect(destination.bodyTemplate.contains("{{config.project}}"))
        #expect(destination.bodyTemplate.contains("{{jiraPriority}}"))
    }

    @Test func slackPresetShape() {
        let destination = DestinationPresetFactory.make(
            preset: .slack, kind: .note, name: "Slack", config: [:])
        #expect(destination.authStyle == .urlSecret)
        #expect(destination.kind == .note)
        #expect(destination.bodyTemplate.contains("{{#items}}"))
    }

    @Test func requiredFieldsListSecrets() {
        let github = DestinationPresetFactory.fields(for: .github, kind: .item)
        #expect(github.contains { $0.key == "repo" && !$0.isSecret })
        #expect(github.contains { $0.isSecret })

        let slack = DestinationPresetFactory.fields(for: .slack, kind: .note)
        #expect(slack.count == 1)
        #expect(slack.first?.isSecret == true)
    }

    @Test func remoteURLExtraction() {
        let github = #"{"html_url": "https://github.com/acme/api/issues/7"}"#
        #expect(DestinationPresetFactory.remoteURL(
            preset: .github, responseData: Data(github.utf8), config: [:])
            == "https://github.com/acme/api/issues/7")

        let jira = #"{"key": "API-42"}"#
        #expect(DestinationPresetFactory.remoteURL(
            preset: .jira, responseData: Data(jira.utf8),
            config: ["site": "https://acme.atlassian.net"])
            == "https://acme.atlassian.net/browse/API-42")

        #expect(DestinationPresetFactory.remoteURL(
            preset: .slack, responseData: Data("ok".utf8), config: [:]) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
LOG=/tmp/dest-t3a.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' \
  -only-testing:RevueAITests/DestinationPresetsTests > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
```

Expected: build errors — `cannot find 'DestinationPresetFactory' in scope`.

- [ ] **Step 3: Implement**

Create `MyApp/Destinations/DestinationPresets.swift`:

```swift
import Foundation

/// One field the user must fill when creating a destination from a preset.
struct PresetField: Equatable, Identifiable {
    let key: String
    let label: String
    let isSecret: Bool
    var placeholder: String = ""
    var id: String { key }
}

/// Factories turning a preset choice into a ready-to-edit Destination,
/// plus per-preset response parsing for the created resource's URL.
enum DestinationPresetFactory {
    static func fields(for preset: DestinationPreset, kind: DestinationKind) -> [PresetField] {
        switch preset {
        case .github:
            return [
                PresetField(key: "repo", label: "Repository (owner/name)", isSecret: false,
                            placeholder: "acme/api"),
                PresetField(key: "secret", label: "Fine-grained personal access token",
                            isSecret: true, placeholder: "github_pat_…"),
            ]
        case .jira:
            return [
                PresetField(key: "site", label: "Site URL", isSecret: false,
                            placeholder: "https://acme.atlassian.net"),
                PresetField(key: "project", label: "Project key", isSecret: false,
                            placeholder: "API"),
                PresetField(key: "secret", label: "Email and API token (email:token)",
                            isSecret: true, placeholder: "you@acme.com:token"),
            ]
        case .slack:
            return [
                PresetField(key: "secret", label: "Incoming webhook URL", isSecret: true,
                            placeholder: "https://hooks.slack.com/services/…"),
            ]
        case .custom:
            return [
                PresetField(key: "url", label: "Request URL", isSecret: false,
                            placeholder: "https://tools.internal/api/notes"),
                PresetField(key: "secret", label: "Auth secret (optional)", isSecret: true),
            ]
        }
    }

    static func make(preset: DestinationPreset,
                     kind: DestinationKind,
                     name: String,
                     config: [String: String]) -> Destination {
        switch preset {
        case .github:
            return Destination(
                name: name, kind: .item, preset: .github,
                urlTemplate: "https://api.github.com/repos/{{config.repo}}/issues",
                headers: [
                    "Accept": "application/vnd.github+json",
                    "Content-Type": "application/json",
                ],
                bodyTemplate: githubBody,
                authStyle: .bearerToken,
                config: config
            )
        case .jira:
            return Destination(
                name: name, kind: .item, preset: .jira,
                urlTemplate: "{{config.site}}/rest/api/3/issue",
                headers: ["Content-Type": "application/json"],
                bodyTemplate: jiraBody,
                authStyle: .basicEmailToken,
                config: config
            )
        case .slack:
            return Destination(
                name: name, kind: .note, preset: .slack,
                urlTemplate: "",
                headers: ["Content-Type": "application/json"],
                bodyTemplate: slackBody,
                authStyle: .urlSecret,
                config: config
            )
        case .custom:
            return Destination(
                name: name, kind: kind, preset: .custom,
                urlTemplate: config["url"] ?? "",
                headers: ["Content-Type": "application/json"],
                bodyTemplate: starterTemplate(for: kind),
                authStyle: .headerValue,
                config: config
            )
        }
    }

    /// Parses the provider response for a link back to the created resource.
    static func remoteURL(preset: DestinationPreset,
                          responseData: Data,
                          config: [String: String]) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: responseData)
                as? [String: Any] else { return nil }
        switch preset {
        case .github:
            return json["html_url"] as? String
        case .jira:
            guard let key = json["key"] as? String,
                  let site = config["site"] else { return nil }
            return "\(site)/browse/\(key)"
        case .slack, .custom:
            return nil
        }
    }

    static func starterTemplate(for kind: DestinationKind) -> String {
        switch kind {
        case .item:
            return #"{"title": "{{oneLiner}}", "detail": "{{rationale}}", "priority": "{{priority}}", "tags": [{{tagsJSONArray}}], "source": "RevueAI — {{noteTitle}}"}"#
        case .note:
            return #"{"title": "{{title}}", "summary": "{{summary}}", "verdict": "{{verdict}}", "openItems": "{{#items}}- {{oneLiner}}\n{{/items}}"}"#
        }
    }

    private static let githubBody = #"""
    {"title": "{{oneLiner}}", "body": "{{rationale}}\n\n{{inDepthDetail}}\n\n_Raised by {{attribution}} in “{{noteTitle}}” ({{noteDate}}) — filed from RevueAI_", "labels": [{{tagsJSONArray}}]}
    """#

    private static let jiraBody = #"""
    {"fields": {"project": {"key": "{{config.project}}"}, "issuetype": {"name": "Task"}, "summary": "{{oneLiner}}", "priority": {"name": "{{jiraPriority}}"}, "description": {"type": "doc", "version": 1, "content": [{"type": "paragraph", "content": [{"type": "text", "text": "{{rationale}} — {{inDepthDetail}} (raised by {{attribution}}, from “{{noteTitle}}”)"}]}]}}}
    """#

    private static let slackBody = #"""
    {"blocks": [{"type": "header", "text": {"type": "plain_text", "text": "{{title}}"}}, {"type": "context", "elements": [{"type": "mrkdwn", "text": "{{verdict}} · {{date}} · {{openCount}} open"}]}, {"type": "section", "text": {"type": "mrkdwn", "text": "{{summary}}"}}, {"type": "section", "text": {"type": "mrkdwn", "text": "*Open items*\n{{#items}}• {{oneLiner}} _({{priority}})_\n{{/items}}"}}]}
    """#
}
```

Note: the GitHub template's literal `\n` sequences inside the raw string
(`#"""…"""#`) stay as backslash-n characters in the template — correct,
because they are *inside JSON string literals* in the rendered body.

- [ ] **Step 4: Run to verify pass**

Same command as Step 2. Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add MyApp/Destinations/DestinationPresets.swift RevueAITests/DestinationPresetsTests.swift
git commit -m "feat: GitHub/Jira/Slack/custom destination preset factories"
```

---

### Task 4: Sender with mock transport

**Files:**
- Create: `MyApp/Destinations/DestinationSender.swift`
- Create: `RevueAITests/Support/MockTransport.swift`
- Test: `RevueAITests/DestinationSenderTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3 (`Destination`, `ExportRecord`, `DestinationSecrets`, `TemplateRenderer`, `TemplateContextBuilder`, `DestinationPresetFactory`).
- Produces: `Transport` protocol (`send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)`), `URLSessionTransport`, `DestinationSender` (`init(transport:secrets:)`, `send(item:to:context:) async throws -> ExportRecord`, `send(note:to:context:) async throws -> ExportRecord`, `sendTest(to:) async throws -> (statusCode: Int, body: String)`, `static hasSuccessfulExport(_ item: ActionItem, to: Destination) -> Bool`), `DestinationSendError` (`.missingSecret`, `.badURL`).

- [ ] **Step 1: Create the mock transport**

Create `RevueAITests/Support/MockTransport.swift`:

```swift
import Foundation
@testable import RevueAI

/// Records requests and replays scripted responses.
final class MockTransport: Transport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var responses: [(Data, Int)] = [(Data("{}".utf8), 201)]

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (data, status) = responses.isEmpty
            ? (Data(), 200) : responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}
```

- [ ] **Step 2: Write the failing tests**

Create `RevueAITests/DestinationSenderTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import RevueAI

@MainActor
struct DestinationSenderTests {
    private func makeFixture() throws -> (ModelContext, ReviewNote, ActionItem, Destination, MockTransport, DestinationSender) {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "API review")
        let item = ActionItem(oneLiner: "Fix pagination", priority: .blocker, tags: ["api"])
        item.note = note
        let destination = DestinationPresetFactory.make(
            preset: .github, kind: .item, name: "GH", config: ["repo": "acme/api"])
        context.insert(note); context.insert(item); context.insert(destination)
        let transport = MockTransport()
        let sender = DestinationSender(transport: transport, secrets: { _ in "TOKEN123" })
        return (context, note, item, destination, transport, sender)
    }

    @Test func buildsAuthorizedRequestAndRecordsSuccess() async throws {
        let (context, _, item, destination, transport, sender) = try makeFixture()
        transport.responses = [(Data(#"{"html_url": "https://github.com/acme/api/issues/7"}"#.utf8), 201)]

        let record = try await sender.send(item: item, to: destination, context: context)

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.github.com/repos/acme/api/issues")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer TOKEN123")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("Fix pagination"))
        #expect((try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) != nil)

        #expect(record.succeeded)
        #expect(record.statusCode == 201)
        #expect(record.remoteURL == "https://github.com/acme/api/issues/7")
        #expect(item.exportRecords?.count == 1)
        #expect(DestinationSender.hasSuccessfulExport(item, to: destination))
    }

    @Test func nonSuccessStatusRecordsFailure() async throws {
        let (context, _, item, destination, transport, sender) = try makeFixture()
        transport.responses = [(Data(#"{"message": "Bad credentials"}"#.utf8), 401)]

        let record = try await sender.send(item: item, to: destination, context: context)
        #expect(!record.succeeded)
        #expect(record.statusCode == 401)
        #expect(record.remoteURL == nil)
        #expect(!DestinationSender.hasSuccessfulExport(item, to: destination))
    }

    @Test func missingSecretThrowsWithoutRecord() async throws {
        let (context, _, item, destination, _, _) = try makeFixture()
        let sender = DestinationSender(transport: MockTransport(), secrets: { _ in nil })

        await #expect(throws: DestinationSendError.self) {
            try await sender.send(item: item, to: destination, context: context)
        }
        #expect(item.exportRecords?.isEmpty != false)
    }

    @Test func urlSecretStyleUsesSecretAsURL() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "API review")
        note.summary = "Fine."
        context.insert(note)
        let slack = DestinationPresetFactory.make(preset: .slack, kind: .note, name: "Slack", config: [:])
        context.insert(slack)
        let transport = MockTransport()
        transport.responses = [(Data("ok".utf8), 200)]
        let sender = DestinationSender(transport: transport,
                                       secrets: { _ in "https://hooks.slack.com/services/T/B/X" })

        let record = try await sender.send(note: note, to: slack, context: context)
        #expect(transport.requests.first?.url?.absoluteString == "https://hooks.slack.com/services/T/B/X")
        #expect(record.succeeded)
        #expect(record.subjectKind == .note)
        #expect(note.exportRecords?.count == 1)
    }

    @Test func basicAuthEncodesEmailToken() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "R")
        let item = ActionItem(oneLiner: "Fix")
        item.note = note
        let jira = DestinationPresetFactory.make(
            preset: .jira, kind: .item, name: "J",
            config: ["site": "https://acme.atlassian.net", "project": "API"])
        context.insert(note); context.insert(item); context.insert(jira)
        let transport = MockTransport()
        transport.responses = [(Data(#"{"key": "API-42"}"#.utf8), 201)]
        let sender = DestinationSender(transport: transport, secrets: { _ in "me@acme.com:tok" })

        let record = try await sender.send(item: item, to: jira, context: context)
        let expected = "Basic " + Data("me@acme.com:tok".utf8).base64EncodedString()
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == expected)
        #expect(record.remoteURL == "https://acme.atlassian.net/browse/API-42")
    }
}
```

- [ ] **Step 3: Run to verify failure**

```bash
LOG=/tmp/dest-t4a.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' \
  -only-testing:RevueAITests/DestinationSenderTests > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
```

Expected: build errors — `cannot find type 'Transport' in scope`, `cannot find 'DestinationSender' in scope`.

- [ ] **Step 4: Implement**

Create `MyApp/Destinations/DestinationSender.swift`:

```swift
import Foundation
import SwiftData

/// Injectable HTTP seam so tests never touch the network.
protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: Transport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

enum DestinationSendError: Error, LocalizedError {
    case missingSecret
    case badURL

    var errorDescription: String? {
        switch self {
        case .missingSecret:
            return "No token saved for this destination — re-enter it in Settings → Destinations."
        case .badURL:
            return "The destination's URL didn't resolve to a valid address."
        }
    }
}

/// Renders a destination's templates for an item or note, sends the
/// request, and records the outcome as an ExportRecord.
@MainActor
struct DestinationSender {
    var transport: Transport = URLSessionTransport()
    var secrets: (UUID) -> String? = { DestinationSecrets.read(for: $0) }

    @discardableResult
    func send(item: ActionItem, to destination: Destination,
              context: ModelContext) async throws -> ExportRecord {
        let vars = TemplateContextBuilder.context(for: item, config: destination.config)
        let record = try await perform(vars: vars, items: [], destination: destination,
                                       subjectKind: .item)
        record.item = item
        record.note = item.note
        context.insert(record)
        try? context.save()
        return record
    }

    @discardableResult
    func send(note: ReviewNote, to destination: Destination,
              context: ModelContext) async throws -> ExportRecord {
        let vars = TemplateContextBuilder.context(for: note, config: destination.config)
        let items = TemplateContextBuilder.itemContexts(for: note)
        let record = try await perform(vars: vars, items: items, destination: destination,
                                       subjectKind: .note)
        record.note = note
        context.insert(record)
        try? context.save()
        return record
    }

    /// Sends a canned sample payload; writes no records. For "Send test".
    func sendTest(to destination: Destination) async throws -> (statusCode: Int, body: String) {
        let sampleItem: [String: String] = [
            "oneLiner": "Sample: tighten the retry backoff",
            "rationale": "Sent by RevueAI to verify this destination.",
            "inDepthDetail": "You can delete this on the receiving side.",
            "attribution": "RevueAI", "priority": "Minor", "category": "Other",
            "tags": "test", "tagsJSONArray": "\"test\"", "jiraPriority": "Low",
            "noteTitle": "Destination test", "noteDate": Date.now.formatted(date: .abbreviated, time: .omitted),
        ]
        var vars: [String: String] = [
            "title": "Destination test", "summary": "Sent by RevueAI to verify this destination.",
            "date": Date.now.formatted(date: .abbreviated, time: .shortened),
            "verdict": "Pending", "durationMinutes": "0",
            "openCount": "1", "doneCount": "0", "decisions": "",
        ]
        vars.merge(sampleItem) { current, _ in current }
        for (key, value) in destination.config { vars["config.\(key)"] = value }
        let request = try buildRequest(vars: vars, items: [sampleItem], destination: destination)
        let (data, response) = try await transport.send(request)
        return (response.statusCode, String(data: data.prefix(500), encoding: .utf8) ?? "")
    }

    static func hasSuccessfulExport(_ item: ActionItem, to destination: Destination) -> Bool {
        (item.exportRecords ?? []).contains {
            $0.succeeded && $0.destinationID == destination.id
        }
    }

    // MARK: - Internals

    private func perform(vars: [String: String], items: [[String: String]],
                         destination: Destination,
                         subjectKind: ExportSubjectKind) async throws -> ExportRecord {
        let request = try buildRequest(vars: vars, items: items, destination: destination)
        let record = ExportRecord(destinationName: destination.name,
                                  destinationID: destination.id,
                                  subjectKind: subjectKind)
        do {
            let (data, response) = try await transport.send(request)
            record.statusCode = response.statusCode
            record.succeeded = (200..<300).contains(response.statusCode)
            if record.succeeded {
                record.remoteURL = DestinationPresetFactory.remoteURL(
                    preset: destination.preset, responseData: data,
                    config: destination.config)
            }
        } catch {
            record.succeeded = false
            record.statusCode = 0
        }
        return record
    }

    private func buildRequest(vars: [String: String], items: [[String: String]],
                              destination: Destination) throws -> URLRequest {
        let needsSecret = destination.authStyle != .none
        let secret = secrets(destination.id)
        if needsSecret && secret == nil { throw DestinationSendError.missingSecret }

        let urlString: String
        if destination.authStyle == .urlSecret {
            urlString = secret ?? ""
        } else {
            urlString = TemplateRenderer.render(destination.urlTemplate,
                                                context: vars, mode: .plain)
        }
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            throw DestinationSendError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = destination.httpMethod
        for (name, value) in destination.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        switch destination.authStyle {
        case .bearerToken:
            request.setValue("Bearer \(secret ?? "")", forHTTPHeaderField: "Authorization")
        case .basicEmailToken:
            let encoded = Data((secret ?? "").utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        case .headerValue:
            let header = destination.config["authHeader"] ?? "Authorization"
            request.setValue(secret ?? "", forHTTPHeaderField: header)
        case .urlSecret, .none:
            break
        }
        let isJSON = (destination.headers["Content-Type"] ?? "").contains("json")
        let body = TemplateRenderer.render(destination.bodyTemplate, context: vars,
                                           items: items, mode: isJSON ? .json : .plain)
        request.httpBody = Data(body.utf8)
        return request
    }
}
```

Note on `.headerValue` + empty secret: `custom` presets may have no
secret; `needsSecret` intentionally treats only `.none` as secret-free, so
custom destinations that truly need no auth should be saved with
`authStyle = .none` (the Settings form in Task 6 does this when the secret
field is left blank).

- [ ] **Step 5: Run to verify pass**

Same command as Step 3. Expected: `TEST SUCCEEDED`.

- [ ] **Step 6: Full suite + commit**

```bash
LOG=/tmp/dest-t4b.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
grep -q "TEST SUCCEEDED" $LOG \
  && git add MyApp/Destinations/DestinationSender.swift \
             RevueAITests/Support/MockTransport.swift RevueAITests/DestinationSenderTests.swift \
  && git commit -m "feat: destination sender — auth styles, response links, export records"
```

---

### Task 5: Auto-rules + polish hook + network entitlement

**Files:**
- Create: `MyApp/Destinations/AutoRuleEngine.swift`
- Modify: `MyApp/CaptureCoordinator.swift:155` (after `finalPolisher.polish` returns)
- Modify: `RevueAI.xcodeproj/project.pbxproj:330,384` (`ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO` → `YES`, both configurations)
- Test: `RevueAITests/AutoRuleEngineTests.swift`

**Interfaces:**
- Consumes: `Destination` (auto-rule fields), `DestinationSender`, `ActionPriority.sortRank` (lower = more urgent).
- Produces: `AutoRuleEngine.itemsToAutoFile(note:destination:) -> [ActionItem]`, `AutoRuleEngine.run(after note: ReviewNote, context: ModelContext, sender: DestinationSender) async`.

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/AutoRuleEngineTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import RevueAI

@MainActor
struct AutoRuleEngineTests {
    @Test func selectsItemsAtOrAboveThresholdWithoutPriorSuccess() throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "R")
        let blocker = ActionItem(oneLiner: "B", priority: .blocker)
        let major = ActionItem(oneLiner: "M", priority: .major)
        let nit = ActionItem(oneLiner: "N", priority: .nit)
        for item in [blocker, major, nit] { item.note = note; context.insert(item) }
        context.insert(note)

        let destination = Destination(name: "GH", kind: .item, preset: .github)
        destination.autoFileMinPriority = .major
        context.insert(destination)

        // Blocker already filed successfully — must be excluded.
        let prior = ExportRecord(destinationName: "GH", destinationID: destination.id,
                                 subjectKind: .item)
        prior.succeeded = true
        prior.item = blocker
        context.insert(prior)

        let selected = AutoRuleEngine.itemsToAutoFile(note: note, destination: destination)
        #expect(selected.map(\.oneLiner) == ["M"])
    }

    @Test func noThresholdSelectsNothing() throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "R")
        let item = ActionItem(oneLiner: "B", priority: .blocker)
        item.note = note
        context.insert(note); context.insert(item)
        let destination = Destination(name: "GH", kind: .item, preset: .github)
        context.insert(destination)

        #expect(AutoRuleEngine.itemsToAutoFile(note: note, destination: destination).isEmpty)
    }

    @Test func runSendsDigestAndFilesItems() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "R")
        note.summary = "S"
        let blocker = ActionItem(oneLiner: "B", priority: .blocker)
        blocker.note = note
        context.insert(note); context.insert(blocker)

        let slack = DestinationPresetFactory.make(preset: .slack, kind: .note, name: "Slack", config: [:])
        slack.autoSendOnPolish = true
        let github = DestinationPresetFactory.make(preset: .github, kind: .item, name: "GH",
                                                   config: ["repo": "a/b"])
        github.autoFileMinPriority = .blocker
        context.insert(slack); context.insert(github)
        try context.save()

        let transport = MockTransport()
        transport.responses = [(Data("ok".utf8), 200), (Data("{}".utf8), 201)]
        let sender = DestinationSender(transport: transport, secrets: { _ in "https://hooks.slack.com/x" })

        await AutoRuleEngine.run(after: note, context: context, sender: sender)

        #expect(transport.requests.count == 2)
        #expect(note.exportRecords?.count == 2)
        #expect(blocker.exportRecords?.count == 1)
    }

    @Test func runWithNoRulesSendsNothing() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "R")
        context.insert(note)
        let transport = MockTransport()
        let sender = DestinationSender(transport: transport, secrets: { _ in "x" })

        await AutoRuleEngine.run(after: note, context: context, sender: sender)
        #expect(transport.requests.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
LOG=/tmp/dest-t5a.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' \
  -only-testing:RevueAITests/AutoRuleEngineTests > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
```

Expected: build errors — `cannot find 'AutoRuleEngine' in scope`.

- [ ] **Step 3: Implement**

Create `MyApp/Destinations/AutoRuleEngine.swift`:

```swift
import Foundation
import SwiftData

/// Evaluates the two per-destination auto-rules when a note's polish
/// completes. Failures are recorded but never block or alert — the UI
/// surfaces them from ExportRecords.
@MainActor
enum AutoRuleEngine {
    /// Open items at/above the destination's priority threshold that have
    /// no prior successful send to it (no duplicate filing).
    static func itemsToAutoFile(note: ReviewNote, destination: Destination) -> [ActionItem] {
        guard destination.kind == .item,
              let threshold = destination.autoFileMinPriority else { return [] }
        return note.sortedActionItems.filter { item in
            !item.isDone
                && item.priority.sortRank <= threshold.sortRank
                && !DestinationSender.hasSuccessfulExport(item, to: destination)
        }
    }

    static func run(after note: ReviewNote, context: ModelContext,
                    sender: DestinationSender = DestinationSender()) async {
        let destinations = (try? context.fetch(FetchDescriptor<Destination>())) ?? []
        for destination in destinations {
            switch destination.kind {
            case .note where destination.autoSendOnPolish:
                _ = try? await sender.send(note: note, to: destination, context: context)
            case .item:
                for item in itemsToAutoFile(note: note, destination: destination) {
                    _ = try? await sender.send(item: item, to: destination, context: context)
                }
            default:
                break
            }
        }
    }
}
```

- [ ] **Step 4: Hook into polish completion**

Re-read `MyApp/CaptureCoordinator.swift` around line 155. The line

```swift
                await finalPolisher.polish(note: note, segments: transcript.segments, context: context)
```

becomes:

```swift
                await finalPolisher.polish(note: note, segments: transcript.segments, context: context)
                await AutoRuleEngine.run(after: note, context: context)
```

- [ ] **Step 5: Enable outgoing network connections**

In `RevueAI.xcodeproj/project.pbxproj`, change **both** occurrences (Debug
line 330 and Release line 384):

```
				ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO;
```

to

```
				ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;
```

- [ ] **Step 6: Full suite + commit**

```bash
LOG=/tmp/dest-t5b.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
grep -q "TEST SUCCEEDED" $LOG \
  && git add MyApp/Destinations/AutoRuleEngine.swift MyApp/CaptureCoordinator.swift \
             RevueAI.xcodeproj/project.pbxproj RevueAITests/AutoRuleEngineTests.swift \
  && git commit -m "feat: auto-rules on polish completion; enable outgoing network"
```

---

### Task 6: Settings — Destinations editor

**Files:**
- Create: `MyApp/Views/DestinationsSettingsView.swift`
- Modify: `MyApp/Views/SettingsView.swift` (add section; widen frame)

View-layer task: gate is a clean build + full suite (models/sender logic is already covered). Re-read `SettingsView.swift` before editing.

- [ ] **Step 1: Create the editor**

Create `MyApp/Views/DestinationsSettingsView.swift`:

```swift
import SwiftUI
import SwiftData

/// Settings section: list, add, edit, and test destinations.
struct DestinationsSettingsSection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Destination.order) private var destinations: [Destination]
    @State private var editing: Destination?
    @State private var addingPreset: DestinationPreset?

    var body: some View {
        Section("Destinations") {
            ForEach(destinations) { destination in
                Button {
                    editing = destination
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: destination.preset.systemImage)
                            .frame(width: 22)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(destination.name)
                                .font(Theme.rounded(13, .semibold))
                            Text(destination.kind == .item ? "Files action items" : "Receives note digests")
                                .font(Theme.rounded(11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Menu("Add Destination…") {
                ForEach(DestinationPreset.allCases) { preset in
                    Button(preset.displayName, systemImage: preset.systemImage) {
                        addingPreset = preset
                    }
                }
            }
        }
        .sheet(item: $editing) { destination in
            DestinationEditorSheet(destination: destination, isNew: false)
        }
        .sheet(item: $addingPreset) { preset in
            DestinationCreateSheet(preset: preset)
        }
    }
}

/// Add flow: minimal per-preset fields, then save (secret → Keychain).
private struct DestinationCreateSheet: View {
    let preset: DestinationPreset
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: DestinationKind = .item
    @State private var values: [String: String] = [:]

    private var fields: [PresetField] {
        DestinationPresetFactory.fields(for: preset, kind: kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add \(preset.displayName) destination")
                .font(.system(size: 16, weight: .bold, design: .rounded))

            TextField("Name", text: $name, prompt: Text(preset.displayName))
                .textFieldStyle(.roundedBorder)

            if preset == .custom {
                Picker("Sends", selection: $kind) {
                    Text("Action items").tag(DestinationKind.item)
                    Text("Note digests").tag(DestinationKind.note)
                }
                .pickerStyle(.segmented)
            }

            ForEach(fields) { field in
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.label)
                        .font(Theme.rounded(11, .medium))
                        .foregroundStyle(.secondary)
                    if field.isSecret {
                        SecureField(field.placeholder, text: binding(field.key))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField(field.placeholder, text: binding(field.key))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(width: 420)
    }

    private var isValid: Bool {
        let nonSecretFilled = fields.filter { !$0.isSecret }
            .allSatisfy { !(values[$0.key] ?? "").isEmpty }
        let secretFilled = preset == .custom
            || !(values["secret"] ?? "").isEmpty
        return nonSecretFilled && secretFilled
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }

    private func save() {
        var config = values
        let secret = config.removeValue(forKey: "secret") ?? ""
        let destination = DestinationPresetFactory.make(
            preset: preset, kind: kind,
            name: name.isEmpty ? preset.displayName : name,
            config: config)
        if preset == .custom && secret.isEmpty {
            destination.authStyle = .none
        }
        destination.order = ((try? context.fetch(FetchDescriptor<Destination>()))?
            .map(\.order).max() ?? -1) + 1
        context.insert(destination)
        if !secret.isEmpty { DestinationSecrets.store(secret, for: destination.id) }
        try? context.save()
        dismiss()
    }
}

/// Edit flow: name, auto-rules, template, token rotation, test, delete.
private struct DestinationEditorSheet: View {
    @Bindable var destination: Destination
    let isNew: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var newSecret = ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: destination.preset.systemImage)
                    .foregroundStyle(Theme.accent)
                TextField("Name", text: $destination.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }

            // Auto-rules
            if destination.kind == .note {
                Toggle("Send digest automatically when a note is polished",
                       isOn: $destination.autoSendOnPolish)
                    .font(Theme.rounded(12))
            } else {
                Picker("Auto-file items at or above", selection: Binding(
                    get: { destination.autoFileMinPriority },
                    set: { destination.autoFileMinPriority = $0 }
                )) {
                    Text("Off").tag(ActionPriority?.none)
                    ForEach(ActionPriority.allCases) { priority in
                        Text(priority.displayName).tag(ActionPriority?.some(priority))
                    }
                }
                .font(Theme.rounded(12))
            }

            DisclosureGroup("Template") {
                TextEditor(text: $destination.bodyTemplate)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 140)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
            }
            .font(Theme.rounded(12, .medium))

            SecureField("Replace saved token / webhook (leave blank to keep)",
                        text: $newSecret)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(testing ? "Sending…" : "Send Test") { runTest() }
                    .disabled(testing)
                if let testResult {
                    Text(testResult)
                        .font(Theme.rounded(11))
                        .foregroundStyle(testResult.hasPrefix("✓") ? Theme.success : Theme.danger)
                        .lineLimit(2)
                }
                Spacer()
            }

            Divider()

            HStack {
                Button(role: .destructive) {
                    DestinationSecrets.delete(for: destination.id)
                    context.delete(destination)
                    try? context.save()
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .foregroundStyle(.red)
                Spacer()
                Button("Done") {
                    if !newSecret.isEmpty {
                        DestinationSecrets.store(newSecret, for: destination.id)
                    }
                    try? context.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    // `DestinationPreset` is already Identifiable (Task 1), so
    // `sheet(item:)` works with it directly — no extra conformance here.

    private func runTest() {
        testing = true
        testResult = nil
        let pendingSecret = newSecret
        let id = destination.id
        if !pendingSecret.isEmpty { DestinationSecrets.store(pendingSecret, for: id) }
        Task {
            defer { testing = false }
            do {
                let sender = DestinationSender()
                let (status, body) = try await sender.sendTest(to: destination)
                testResult = (200..<300).contains(status)
                    ? "✓ \(status)"
                    : "✗ \(status): \(body.prefix(120))"
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
        }
    }
}
```

- [ ] **Step 2: Integrate into SettingsView**

Re-read `MyApp/Views/SettingsView.swift`. Inside the `Form`, after the
`Section("Capture")`, add:

```swift
            DestinationsSettingsSection()
```

and change the frame to fit the richer content:

```swift
        .frame(width: 440, height: 420)
```

(replacing `.frame(width: 380)`).

- [ ] **Step 3: Full suite + commit**

```bash
LOG=/tmp/dest-t6.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
grep -q "TEST SUCCEEDED" $LOG \
  && git add MyApp/Views/DestinationsSettingsView.swift MyApp/Views/SettingsView.swift \
  && git commit -m "feat: destinations editor in Settings — presets, templates, test send"
```

---

### Task 7: Dock swap — calendar to toolbar, destinations strip

**Files:**
- Create: `MyApp/Views/DestinationDock.swift`
- Modify: `MyApp/Views/LibraryView.swift` (bottom dock content + calendar toolbar item)

Re-read `LibraryView.swift` immediately before editing. View-layer task:
gate is a clean build + full suite.

- [ ] **Step 1: Create the dock strip**

Create `MyApp/Views/DestinationDock.swift`:

```swift
import SwiftUI
import SwiftData

/// The sidebar's bottom strip: one glass chip per destination. Item-kind
/// chips accept action-item drops (drag-to-file, same drag language as the
/// board). Chips pulse on success and carry a red dot after a failure.
struct DestinationDock: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Destination.order) private var destinations: [Destination]
    @State private var pulsing: UUID?
    @State private var failed: Set<UUID> = []

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if destinations.isEmpty {
                    SettingsLink {
                        Label("Add a destination", systemImage: "plus")
                            .font(Theme.rounded(12, .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .glassEffect(.regular, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .help("Open Settings to add GitHub, Jira, Slack, or a custom destination")
                } else {
                    ForEach(destinations) { destination in
                        chip(destination)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 40)
    }

    private func chip(_ destination: Destination) -> some View {
        HStack(spacing: 6) {
            Image(systemName: destination.preset.systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(destination.name)
                .font(Theme.rounded(12, .medium))
            if failed.contains(destination.id) {
                Circle().fill(.red).frame(width: 6, height: 6)
            }
        }
        .foregroundStyle(pulsing == destination.id ? Theme.success : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(pulsing == destination.id
                     ? .regular.tint(Theme.success.opacity(0.25)) : .regular,
                     in: .capsule)
        .help(destination.kind == .item
              ? "Drop an action item here to file it to \(destination.name)"
              : "Receives note digests")
        .modifier(ItemDropIfSupported(destination: destination, onDrop: file))
        .animation(.smooth(duration: 0.3), value: pulsing)
    }

    private func file(_ transfers: [ActionItemTransfer], to destination: Destination) {
        let ids = transfers.map(\.id)
        let items = (try? context.fetch(FetchDescriptor<ActionItem>()))?
            .filter { ids.contains($0.id) } ?? []
        guard !items.isEmpty else { return }
        Task {
            var allSucceeded = true
            for item in items {
                let record = try? await DestinationSender().send(
                    item: item, to: destination, context: context)
                if record?.succeeded != true { allSucceeded = false }
            }
            if allSucceeded {
                failed.remove(destination.id)
                pulsing = destination.id
                try? await Task.sleep(for: .seconds(1.2))
                pulsing = nil
            } else {
                failed.insert(destination.id)
            }
        }
    }
}

/// Item-kind chips accept dropped action items; note-kind chips don't.
private struct ItemDropIfSupported: ViewModifier {
    let destination: Destination
    let onDrop: ([ActionItemTransfer], Destination) -> Void

    func body(content: Content) -> some View {
        if destination.kind == .item {
            content.dropDestination(for: ActionItemTransfer.self) { transfers, _ in
                onDrop(transfers, destination)
                return true
            }
        } else {
            content
        }
    }
}
```

- [ ] **Step 2: Swap the dock and move the calendar**

In `MyApp/Views/LibraryView.swift`:

1. Add state for the calendar popover near the other `@State` properties:

```swift
    @State private var showCalendar = false
```

2. Replace the `bottomDock` body: the `DateRulerView(...)` call chain
   (with `.tourAnchor("date-ruler")` and the padding lines *before*
   `.background {`) becomes:

```swift
        DestinationDock()
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .padding(.top, 4)
```

   keeping the existing `.background { … }` progressive-blur scrim
   exactly as is.

3. In `libraryToolbar`, after the archive `ToolbarItem`, add:

```swift
        ToolbarItem(placement: .automatic) {
            Button {
                showCalendar.toggle()
            } label: {
                Label("Calendar", systemImage: "calendar")
            }
            .help("Date ruler — scrub history, filter by day, arm meetings")
            .tourAnchor("date-ruler")
            .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                DateRulerView(model: calendarModel,
                              filterDay: $filterDay,
                              onOpenNote: { selection = $0 },
                              onArmChanged: onArmChanged)
                    .frame(width: 340)
                    .padding(10)
            }
        }
```

Note: the tour anchor moves to the calendar *button*, so Act 1's ruler
stop now spotlights the toolbar button that opens it — update nothing
else; the anchor id is unchanged.

- [ ] **Step 3: Full suite + commit**

```bash
LOG=/tmp/dest-t7.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' > $LOG 2>&1
grep -E "error:|TEST (SUCCEEDED|FAILED)" $LOG | head
grep -q "TEST SUCCEEDED" $LOG \
  && git add MyApp/Views/DestinationDock.swift MyApp/Views/LibraryView.swift \
  && git commit -m "feat: dock swap — calendar in toolbar popover, destinations strip with drag-to-file"
```

---

### Task 8: Send surfaces — item popover, board menu, export menu — and verification

**Files:**
- Modify: `MyApp/Views/ItemPopup.swift` ("File to…" menu + sent chip in `ActionItemDetail` footer)
- Modify: `MyApp/Views/ActionItemBoard.swift` (context-menu file entries)
- Modify: `MyApp/Views/Shell/RootShellView.swift` (export menu "Send to…" entries + history sheet)
- Create: `MyApp/Views/ExportHistorySheet.swift` (sent history with retry)

Re-read each file immediately before editing. Gate: full suite + push.

- [ ] **Step 1: Item popover — file menu and sent chip**

In `MyApp/Views/ItemPopup.swift`, `ActionItemDetail`:

1. Add to the properties:

```swift
    @Query(sort: \Destination.order) private var destinations: [Destination]
    @State private var confirmRefile: Destination?
```

   and add `import SwiftData` if not present (it is — the file already
   imports it).

2. In `footer`, before the Delete button (after the `Spacer()`), insert:

```swift
            if let sent = (item.exportRecords ?? [])
                .filter(\.succeeded)
                .sorted(by: { $0.date > $1.date })
                .first, let remote = sent.remoteURL, let url = URL(string: remote) {
                Link(destination: url) {
                    Label(sent.destinationName, systemImage: "arrow.up.forward.square")
                        .font(Theme.rounded(11, .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular.tint(Theme.success.opacity(0.18)), in: .capsule)
                }
                .foregroundStyle(Theme.success)
                .help("Filed to \(sent.destinationName) — click to open")
            }

            let itemDestinations = destinations.filter { $0.kind == .item }
            if !itemDestinations.isEmpty {
                Menu {
                    ForEach(itemDestinations) { destination in
                        Button(destination.name, systemImage: destination.preset.systemImage) {
                            if DestinationSender.hasSuccessfulExport(item, to: destination) {
                                confirmRefile = destination
                            } else {
                                file(to: destination)
                            }
                        }
                    }
                } label: {
                    Label("File to", systemImage: "paperplane")
                        .font(Theme.rounded(11, .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .confirmationDialog(
                    "Already filed to \(confirmRefile?.name ?? "this destination") — file again?",
                    isPresented: Binding(
                        get: { confirmRefile != nil },
                        set: { if !$0 { confirmRefile = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("File again") {
                        if let destination = confirmRefile { file(to: destination) }
                        confirmRefile = nil
                    }
                    Button("Cancel", role: .cancel) { confirmRefile = nil }
                }
            }
```

3. Add the helper method to `ActionItemDetail`:

```swift
    private func file(to destination: Destination) {
        Task { _ = try? await DestinationSender().send(item: item, to: destination, context: context) }
    }
```

- [ ] **Step 2: Board context menu**

In `MyApp/Views/ActionItemBoard.swift`, `ReviewBoard` gains:

```swift
    @Query(sort: \Destination.order) private var destinations: [Destination]
```

and inside `actionColumn`'s `.contextMenu` block, after the existing
`Button("Move down")` entry, add:

```swift
                    let itemDestinations = destinations.filter { $0.kind == .item }
                    if !itemDestinations.isEmpty {
                        Divider()
                        ForEach(itemDestinations) { destination in
                            Button("File to \(destination.name)") {
                                Task {
                                    _ = try? await DestinationSender().send(
                                        item: item, to: destination, context: context)
                                }
                            }
                        }
                    }
```

- [ ] **Step 3: Export menu — send note**

In `MyApp/Views/Shell/RootShellView.swift`:

1. Add to the properties:

```swift
    @Query(sort: \Destination.order) private var noteDestinationsQuery: [Destination]
```

2. In `exportMenu`'s `Menu { … }`, after the existing export section, add:

```swift
            let noteDestinations = noteDestinationsQuery.filter { $0.kind == .note }
            if let note = selection, !noteDestinations.isEmpty {
                Section("Send") {
                    ForEach(noteDestinations) { destination in
                        Button("Send to \(destination.name)",
                               systemImage: destination.preset.systemImage) {
                            Task {
                                _ = try? await DestinationSender().send(
                                    note: note, to: destination, context: context)
                            }
                        }
                    }
                }
            }
```

- [ ] **Step 4: Sent history sheet**

Create `MyApp/Views/ExportHistorySheet.swift`:

```swift
import SwiftUI
import SwiftData

/// Every send for the selected note (digests and item files), newest
/// first, with links to the created resources and retry for failures.
struct ExportHistorySheet: View {
    let note: ReviewNote
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var records: [ExportRecord] {
        (note.exportRecords ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SENT HISTORY")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(.secondary)

            if records.isEmpty {
                Text("Nothing sent from this note yet.")
                    .font(Theme.rounded(12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(records) { record in
                            row(record)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private func row(_ record: ExportRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(record.succeeded ? Theme.success : Theme.danger)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(record.subjectKind == .item ? (record.item?.oneLiner ?? "Item") : "Note digest") → \(record.destinationName)")
                    .font(Theme.rounded(12, .medium))
                    .lineLimit(1)
                Text(record.date.formatted(date: .abbreviated, time: .shortened)
                     + (record.succeeded ? "" : " · HTTP \(record.statusCode)"))
                    .font(Theme.rounded(10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let remote = record.remoteURL, let url = URL(string: remote) {
                Link("Open", destination: url)
                    .font(Theme.rounded(11, .medium))
            } else if !record.succeeded {
                Button("Retry") { retry(record) }
                    .font(Theme.rounded(11, .medium))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }

    private func retry(_ record: ExportRecord) {
        let destinations = (try? context.fetch(FetchDescriptor<Destination>())) ?? []
        guard let destination = destinations.first(where: { $0.id == record.destinationID }) else { return }
        Task {
            let sender = DestinationSender()
            if record.subjectKind == .item, let item = record.item {
                _ = try? await sender.send(item: item, to: destination, context: context)
            } else {
                _ = try? await sender.send(note: note, to: destination, context: context)
            }
        }
    }
}
```

In `MyApp/Views/Shell/RootShellView.swift`:

1. Add state near the other `@State` properties:

```swift
    @State private var showExportHistory = false
```

2. In `exportMenu`'s `Menu { … }`, after the "Send" section added in
   Step 3, append:

```swift
            if selection != nil {
                Divider()
                Button("View Sent History…", systemImage: "clock.arrow.circlepath") {
                    showExportHistory = true
                }
            }
```

3. On the view that already hosts the sheets/overlays (the
   `NavigationSplitView` modifier chain, e.g. right after the onboarding
   `.sheet`), add:

```swift
        .sheet(isPresented: $showExportHistory) {
            if let note = selection {
                ExportHistorySheet(note: note)
            }
        }
```

- [ ] **Step 5: Full suite + commit + push**

```bash
LOG=/tmp/dest-t8.log
xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' > $LOG 2>&1
grep -E "error:|Test run|TEST (SUCCEEDED|FAILED)" $LOG | head
grep -q "TEST SUCCEEDED" $LOG \
  && git add MyApp/Views/ItemPopup.swift MyApp/Views/ActionItemBoard.swift \
             MyApp/Views/Shell/RootShellView.swift MyApp/Views/ExportHistorySheet.swift \
  && git commit -m "feat: send surfaces — file-to menu, board entries, note send, sent history" \
  && git push origin main
```

- [ ] **Step 6: Manual verification checklist (user, via ⌘R)**

1. Settings → Destinations: add a GitHub destination with a real repo +
   PAT; "Send Test" returns ✓ 201 and a test issue appears in the repo.
2. Add a Slack destination with a webhook; Send Test posts to the channel.
3. Item popover → "File to" → GitHub: issue created; green chip links to
   it; re-filing asks for confirmation.
4. Drag an action item from the board onto the GitHub chip in the dock:
   chip pulses green, issue created. Break the token → red dot appears.
5. Export menu → "Send to Slack": digest lands in the channel.
6. Calendar toolbar button opens the ruler popover; scrubbing/filter/
   agenda/arming all still work; tour Act 1 spotlights the button.
7. Enable "auto-send digest" on Slack, capture a short note, stop:
   digest posts when polish completes.
8. Export menu → "View Sent History…": all sends listed with links;
   a failed send shows Retry, and retrying after fixing the token
   succeeds.
