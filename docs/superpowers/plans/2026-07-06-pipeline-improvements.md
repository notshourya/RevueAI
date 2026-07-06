# RevueAI Pipeline Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the capture→extraction pipeline survive real 30–60 min meetings (windowed final pass, live-chunk retry), persist decisions and refined speaker attribution, cut extraction latency, and put a unit-test harness at every pipeline seam.

**Architecture:** All changes sit behind the existing protocol seams (`TranscriptionProviding`, `SpeakerAttribution`, `ReviewLanguageModel`). A new pure `TranscriptWindower` + a `contextTokenBudget` per backend lets `FinalPolisher` map-reduce transcripts that exceed the on-device context window; the same machinery collapses to a single call under PCC's larger budget. A new `RevueAITests` unit-test target (app-hosted, Swift Testing) with fakes behind the seams covers every stage.

**Tech Stack:** Swift 5 mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SwiftUI, SwiftData, FoundationModels (`@Generable` guided generation), Swift Testing (`import Testing`, `@Test`, `#expect`), xcodebuild.

**Spec:** `docs/superpowers/specs/2026-07-06-pipeline-improvements-design.md`

## Global Constraints

- Platform: macOS 27 only; `MACOSX_DEPLOYMENT_TARGET = 27.0`; Xcode 27 beta.
- The app module is named `RevueAI` (target `RevueAI`, `PRODUCT_NAME = "$(TARGET_NAME)"`); tests use `@testable import RevueAI`.
- Both targets build with default MainActor isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`); types that must run off-main are explicitly `nonisolated` (see `OnDeviceReviewModel`).
- **Privacy invariant:** no new persistence path for audio or transcript text. `AudioSegment` and `RollingTranscript` stay memory-only. Supporting quotes inside persisted items are the only verbatim text allowed to persist.
- **CloudKit-safe schema:** no unique constraints; every relationship optional; defaults on every stored property (match `OpenQuestion`'s shape for new models).
- Test command (used in every task): `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`. Success prints `** TEST SUCCEEDED **`.
- Build check command: `xcodebuild build -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`. Success prints `** BUILD SUCCEEDED **`.
- Commit after every task with the message given in its final step.

---

### Task 1: RevueAITests target + shared scheme + smoke test

Creates the unit-test target (app-hosted, synchronized folder) by editing `project.pbxproj`, adds a shared scheme so `xcodebuild test` works, and proves it with a smoke test.

**Files:**
- Create: `RevueAITests/SmokeTests.swift`
- Modify: `RevueAI.xcodeproj/project.pbxproj`
- Create: `RevueAI.xcodeproj/xcshareddata/xcschemes/RevueAI.xcscheme`

**Interfaces:**
- Consumes: existing `RollingTranscript` (`@MainActor final class`, `var isEmpty: Bool`).
- Produces: a runnable `RevueAITests` target every later task adds test files to (folder `RevueAITests/` is a synchronized group — new `.swift` files under it are picked up automatically, no pbxproj edits ever again).

- [ ] **Step 1: Create the smoke test**

Create `RevueAITests/SmokeTests.swift`:

```swift
import Testing
@testable import RevueAI

struct SmokeTests {
    @Test func rollingTranscriptStartsEmpty() {
        let transcript = RollingTranscript()
        #expect(transcript.isEmpty)
    }
}
```

- [ ] **Step 2: Verify tests can't run yet**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: FAIL — either "Scheme RevueAI is not currently configured for the test action" or "cannot find scheme".

- [ ] **Step 3: Add the test target to project.pbxproj**

All edits to `RevueAI.xcodeproj/project.pbxproj`. The new IDs all start with `4D7E57`.

3a. After the line `/* End PBXFileReference section */`, insert a new section:

```
/* Begin PBXContainerItemProxy section */
		4D7E57000000000000000131 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 000000000000000000000000 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 000000000000000100000000;
			remoteInfo = RevueAI;
		};
/* End PBXContainerItemProxy section */
```

3b. Inside the `PBXFileReference` section, after the `RevueAI-Info.plist` line, add:

```
		4D7E57000000000000000120 /* RevueAITests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = RevueAITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
```

3c. Inside the `PBXFileSystemSynchronizedRootGroup` section, after the closing `};` of the `MyApp` entry, add:

```
		4D7E57000000000000000010 /* RevueAITests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = RevueAITests;
			sourceTree = "<group>";
		};
```

3d. Inside the `PBXFrameworksBuildPhase` section, after the closing `};` of the existing entry, add:

```
		4D7E57000000000000000122 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			files = (
			);
		};
```

3e. In the main `PBXGroup` (id `000000000000000000000001`), add the tests group after the `MyApp` child line:

```
				000000000000000000000010 /* MyApp */,
				4D7E57000000000000000010 /* RevueAITests */,
```

3f. In the `Products` group (id `000000000000000000000020`), add after the `RevueAI.app` child:

```
				4D7E57000000000000000120 /* RevueAITests.xctest */,
```

3g. In the `PBXNativeTarget` section, after the closing `};` of the `RevueAI` target, add:

```
		4D7E57000000000000000100 /* RevueAITests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 4D7E57000000000000000110 /* Build configuration list for PBXNativeTarget "RevueAITests" */;
			buildPhases = (
				4D7E57000000000000000121 /* Sources */,
				4D7E57000000000000000122 /* Frameworks */,
				4D7E57000000000000000123 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				4D7E57000000000000000132 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				4D7E57000000000000000010 /* RevueAITests */,
			);
			name = RevueAITests;
			productName = RevueAITests;
			productReference = 4D7E57000000000000000120 /* RevueAITests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
```

3h. In `PBXProject.attributes.TargetAttributes`, after the existing `000000000000000100000000 = {...};` entry, add:

```
					4D7E57000000000000000100 = {
						CreatedOnToolsVersion = 27.0;
						TestTargetID = 000000000000000100000000;
					};
```

3i. In `PBXProject.targets`, after the `RevueAI` entry, add:

```
				4D7E57000000000000000100 /* RevueAITests */,
```

3j. Inside the `PBXResourcesBuildPhase` section, after the closing `};` of the existing entry, add:

```
		4D7E57000000000000000123 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			files = (
			);
		};
```

3k. Inside the `PBXSourcesBuildPhase` section, after the closing `};` of the existing entry, add:

```
		4D7E57000000000000000121 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			files = (
			);
		};
```

3l. After the line `/* End PBXSourcesBuildPhase section */`, insert a new section:

```
/* Begin PBXTargetDependency section */
		4D7E57000000000000000132 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 000000000000000100000000 /* RevueAI */;
			targetProxy = 4D7E57000000000000000131 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */
```

3m. In the `XCBuildConfiguration` section, after the closing `};` of the Release configuration for PBXNativeTarget "RevueAI" (id `000000000000000112000000`), add:

```
		4D7E57000000000000000111 /* Debug configuration for PBXNativeTarget "RevueAITests" */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = SF5MFV26TD;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.thakurshourya.RevueAITests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = macosx;
				SUPPORTED_PLATFORMS = macosx;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
				SWIFT_VERSION = 5.0;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/RevueAI.app/Contents/MacOS/RevueAI";
			};
			name = Debug;
		};
		4D7E57000000000000000112 /* Release configuration for PBXNativeTarget "RevueAITests" */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = SF5MFV26TD;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.thakurshourya.RevueAITests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = macosx;
				SUPPORTED_PLATFORMS = macosx;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
				SWIFT_VERSION = 5.0;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/RevueAI.app/Contents/MacOS/RevueAI";
			};
			name = Release;
		};
```

3n. In the `XCConfigurationList` section, after the closing `};` of the RevueAI target's list (id `000000000000000110000000`), add:

```
		4D7E57000000000000000110 /* Build configuration list for PBXNativeTarget "RevueAITests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				4D7E57000000000000000111 /* Debug configuration for PBXNativeTarget "RevueAITests" */,
				4D7E57000000000000000112 /* Release configuration for PBXNativeTarget "RevueAITests" */,
			);
			defaultConfigurationName = Release;
		};
```

- [ ] **Step 4: Create the shared scheme**

Create `RevueAI.xcodeproj/xcshareddata/xcschemes/RevueAI.xcscheme`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2700"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "000000000000000100000000"
               BuildableName = "RevueAI.app"
               BlueprintName = "RevueAI"
               ReferencedContainer = "container:RevueAI.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "4D7E57000000000000000100"
               BuildableName = "RevueAITests.xctest"
               BlueprintName = "RevueAITests"
               ReferencedContainer = "container:RevueAI.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "000000000000000100000000"
            BuildableName = "RevueAI.app"
            BlueprintName = "RevueAI"
            ReferencedContainer = "container:RevueAI.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

- [ ] **Step 5: Run the tests**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **` with 1 test passing.

Troubleshooting: if code signing fails on the test bundle, the Mac may lack a signing certificate for team `SF5MFV26TD` — ask the user to open the project once in Xcode (Signing & Capabilities → RevueAITests) rather than fighting it from the CLI.

- [ ] **Step 6: Commit**

```bash
git add RevueAITests RevueAI.xcodeproj
git commit -m "test: add RevueAITests unit-test target with shared scheme"
```

---

### Task 2: Fakes + baseline tests for existing pipeline behavior

Locks in current behavior before any change: fakes behind `ReviewLanguageModel` / `TranscriptionProviding`, an in-memory SwiftData helper, and tests for `RollingTranscript`, `LiveExtractor`, `FinalPolisher`, `MarkdownExporter`, and the `CaptureCoordinator` lifecycle.

**Files:**
- Create: `RevueAITests/Support/TestSupport.swift`
- Create: `RevueAITests/Support/FakeReviewModel.swift`
- Create: `RevueAITests/Support/FailingTranscriptionService.swift`
- Create: `RevueAITests/RollingTranscriptTests.swift`
- Create: `RevueAITests/LiveExtractorTests.swift`
- Create: `RevueAITests/FinalPolisherTests.swift`
- Create: `RevueAITests/MarkdownExporterTests.swift`
- Create: `RevueAITests/CaptureCoordinatorTests.swift`
- Delete: `RevueAITests/SmokeTests.swift` (superseded by RollingTranscriptTests)

**Interfaces:**
- Consumes: `ReviewLanguageModel` (`extractPoints(fromChunk:knownPoints:) async throws -> ExtractedPoints`, `polish(transcript:livePoints:) async throws -> PolishedReview`, `var isAvailable: Bool`), `TranscriptionProviding` (`start() async throws -> AsyncThrowingStream<String, Error>`, `stop() async`), `MockTranscriptionService(phrases:interval:)` from the app module, `CaptureCoordinator(transcription:systemTranscription:attribution:model:)`.
- Produces (later tasks rely on these exact names): `makeInMemoryContext() throws -> ModelContext`; `FakeReviewModel` with `extractResults: [Result<ExtractedPoints, FakeModelError>]`, `polishResults: [Result<PolishedReview, FakeModelError>]`, `extractCalls: [ExtractCall]`, `polishCalls: [PolishCall]`; `FailingTranscriptionService`; `ExtractedPoints.empty`; `PolishedReview.stub(...)`; `PolishedActionItem.stub(...)`.

- [ ] **Step 1: Write the support files**

Create `RevueAITests/Support/TestSupport.swift`:

```swift
import Foundation
import SwiftData
@testable import RevueAI

/// A fresh in-memory SwiftData context mirroring the app's schema.
func makeInMemoryContext() throws -> ModelContext {
    let schema = Schema([
        ReviewNote.self,
        ActionItem.self,
        OpenQuestion.self,
        Speaker.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return ModelContext(container)
}

extension ExtractedPoints {
    static var empty: ExtractedPoints {
        ExtractedPoints(actionItems: [], decisions: [], openQuestions: [])
    }
}

extension PolishedReview {
    static func stub(
        summary: String = "A solid review.",
        verdict: GenerableVerdict = .needsChanges,
        actionItems: [PolishedActionItem] = [],
        openQuestions: [OpenQuestionCandidate] = []
    ) -> PolishedReview {
        PolishedReview(
            summary: summary,
            verdict: verdict,
            actionItems: actionItems,
            openQuestions: openQuestions
        )
    }
}

extension PolishedActionItem {
    static func stub(
        _ oneLiner: String,
        attribution: String = "Reviewer",
        priority: GenerablePriority = .major,
        category: GenerableCategory = .bug,
        quotes: [String] = []
    ) -> PolishedActionItem {
        PolishedActionItem(
            oneLiner: oneLiner,
            rationale: "Because it matters.",
            inDepthDetail: "Detail.",
            attribution: attribution,
            supportingQuotes: quotes,
            priority: priority,
            category: category
        )
    }
}
```

Create `RevueAITests/Support/FakeReviewModel.swift`:

```swift
import Foundation
@testable import RevueAI

struct FakeModelError: Error {}

/// Scriptable `ReviewLanguageModel`: returns queued canned results (FIFO),
/// records every call. An empty extract queue yields `.empty`; an empty
/// polish queue throws.
final class FakeReviewModel: ReviewLanguageModel {
    struct ExtractCall { let chunk: String; let knownPoints: String }
    struct PolishCall { let transcript: String; let livePoints: String }

    var isAvailable = true
    var extractResults: [Result<ExtractedPoints, FakeModelError>] = []
    var polishResults: [Result<PolishedReview, FakeModelError>] = []
    private(set) var extractCalls: [ExtractCall] = []
    private(set) var polishCalls: [PolishCall] = []

    func extractPoints(fromChunk chunk: String, knownPoints: String) async throws -> ExtractedPoints {
        extractCalls.append(ExtractCall(chunk: chunk, knownPoints: knownPoints))
        guard !extractResults.isEmpty else { return .empty }
        return try extractResults.removeFirst().get()
    }

    func polish(transcript: String, livePoints: String) async throws -> PolishedReview {
        polishCalls.append(PolishCall(transcript: transcript, livePoints: livePoints))
        guard !polishResults.isEmpty else { throw FakeModelError() }
        return try polishResults.removeFirst().get()
    }
}
```

Create `RevueAITests/Support/FailingTranscriptionService.swift`:

```swift
import Foundation
@testable import RevueAI

/// A transcription source whose `start()` always throws — simulates a denied
/// system-audio tap or missing entitlement.
final class FailingTranscriptionService: TranscriptionProviding {
    struct Unavailable: LocalizedError {
        var errorDescription: String? { "System audio unavailable" }
    }

    func start() async throws -> AsyncThrowingStream<String, Error> {
        throw Unavailable()
    }

    func stop() async {}
}
```

- [ ] **Step 2: Write the baseline tests**

Create `RevueAITests/RollingTranscriptTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct RollingTranscriptTests {
    private func seg(_ text: String, hint: SpeakerHint = .presenter) -> AudioSegment {
        AudioSegment(speakerHint: hint, text: text)
    }

    @Test func drainReturnsOnlyFreshSegmentsOnce() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        transcript.append(seg("two"))
        #expect(transcript.drainNewSegments().map(\.text) == ["one", "two"])
        #expect(transcript.drainNewSegments().isEmpty)
        transcript.append(seg("three"))
        #expect(transcript.drainNewSegments().map(\.text) == ["three"])
    }

    @Test func fullTextFormatsAttributedLines() {
        let transcript = RollingTranscript()
        transcript.append(seg("hello", hint: .presenter))
        transcript.append(seg("hi there", hint: .reviewer))
        #expect(transcript.fullText() == "[presenter] hello\n[reviewer] hi there")
    }

    @Test func clearResetsEverything() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        _ = transcript.drainNewSegments()
        transcript.clear()
        #expect(transcript.isEmpty)
        #expect(transcript.drainNewSegments().isEmpty)
    }
}
```

Create `RevueAITests/LiveExtractorTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct LiveExtractorTests {
    @Test func checkpointsExtractedPointsToTheNote() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let model = FakeReviewModel()
        model.extractResults = [.success(ExtractedPoints(
            actionItems: [ActionItemCandidate(
                oneLiner: "Add index to users table",
                attribution: "Reviewer",
                supportingQuote: "this query is slow"
            )],
            decisions: [],
            openQuestions: [OpenQuestionCandidate(
                question: "Do we need pagination?",
                attribution: "Reviewer"
            )]
        ))]
        let extractor = LiveExtractor(model: model)
        try await extractor.extractAndCheckpoint(
            chunk: "[reviewer] this query is slow",
            into: note,
            context: context
        )
        #expect(note.sortedActionItems.map(\.oneLiner) == ["Add index to users table"])
        #expect(note.sortedActionItems.first?.supportingQuotes == ["this query is slow"])
        #expect(note.sortedOpenQuestions.map(\.text) == ["Do we need pagination?"])
    }

    @Test func sendsKnownPointsToTheModel() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let existing = ActionItem(oneLiner: "Fix crash on launch", order: 0)
        existing.note = note
        context.insert(existing)
        let model = FakeReviewModel()
        let extractor = LiveExtractor(model: model)
        try await extractor.extractAndCheckpoint(chunk: "[presenter] more talk", into: note, context: context)
        let known = try #require(model.extractCalls.first?.knownPoints)
        #expect(known.contains("- Fix crash on launch"))
    }
}
```

Create `RevueAITests/FinalPolisherTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct FinalPolisherTests {
    @Test func successAppliesSummaryVerdictAndItems() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T", status: .capturing)
        context.insert(note)
        let stale = ActionItem(oneLiner: "Stale live point", order: 0)
        stale.note = note
        context.insert(stale)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(
            summary: "Reviewed the upload path.",
            verdict: .approved,
            actionItems: [.stub("Add retry logic to the upload path")]
        ))]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, transcript: "[presenter] hello", context: context)
        #expect(note.summary == "Reviewed the upload path.")
        #expect(note.verdict == .approved)
        #expect(note.status == .processedOnDevice)
        #expect(note.sortedActionItems.map(\.oneLiner) == ["Add retry logic to the upload path"])
    }

    @Test func failureKeepsLivePointsAndMarksOnDevice() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T", status: .capturing)
        context.insert(note)
        let item = ActionItem(oneLiner: "Fix retry logic", order: 0)
        item.note = note
        context.insert(item)
        let model = FakeReviewModel()
        model.polishResults = [.failure(FakeModelError())]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, transcript: "[presenter] hello", context: context)
        #expect(note.status == .processedOnDevice)
        #expect(note.sortedActionItems.map(\.oneLiner) == ["Fix retry logic"])
    }

    @Test func nearDuplicateItemsAreMerged() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(actionItems: [
            .stub("Add retry logic to the upload path"),
            .stub("Add retry logic to upload path"),
        ]))]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, transcript: "[presenter] hello", context: context)
        #expect(note.sortedActionItems.count == 1)
    }
}
```

Create `RevueAITests/MarkdownExporterTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct MarkdownExporterTests {
    @Test func rendersHeaderItemsAndQuestions() throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "API Review", summary: "Looked at the API.", verdict: .needsChanges)
        context.insert(note)
        let item = ActionItem(
            oneLiner: "Add retry logic",
            rationale: "Uploads fail on flaky networks.",
            inDepthDetail: "Wrap the upload call in exponential backoff.",
            attribution: "Reviewer 1",
            supportingQuotes: ["this will fail on bad wifi"],
            order: 0
        )
        item.note = note
        context.insert(item)
        let question = OpenQuestion(text: "Do we need pagination?", attribution: "Reviewer 1", order: 0)
        question.note = note
        context.insert(question)

        let markdown = MarkdownExporter.markdown(for: note)
        #expect(markdown.contains("# API Review"))
        #expect(markdown.contains("## Summary"))
        #expect(markdown.contains("## Action Items"))
        #expect(markdown.contains("**Add retry logic**"))
        #expect(markdown.contains("> this will fail on bad wifi"))
        #expect(markdown.contains("## Open Questions"))
        #expect(markdown.contains("Do we need pagination?"))
    }
}
```

Create `RevueAITests/CaptureCoordinatorTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import RevueAI

struct CaptureCoordinatorTests {
    @Test func fullLifecycleProducesPolishedNote() async throws {
        let context = try makeInMemoryContext()
        let mic = MockTranscriptionService(
            phrases: ["We need retry logic", "Ship it after that"],
            interval: .milliseconds(5)
        )
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(
            summary: "Reviewed the upload path.",
            actionItems: [.stub("Add retry logic to the upload path")]
        ))]
        let coordinator = CaptureCoordinator(
            transcription: mic,
            systemTranscription: FailingTranscriptionService(),
            model: model
        )
        coordinator.captureSystemAudio = false

        await coordinator.start(context: context)
        #expect(coordinator.state == .listening)
        try await Task.sleep(for: .milliseconds(150))
        #expect(coordinator.capturedPhraseCount == 2)

        await coordinator.stop()
        #expect(coordinator.state == .idle)
        let note = try #require(try context.fetch(FetchDescriptor<ReviewNote>()).first)
        #expect(note.summary == "Reviewed the upload path.")
        #expect(note.sortedActionItems.map(\.oneLiner) == ["Add retry logic to the upload path"])
        #expect(coordinator.lastSummary == "Reviewed the upload path.")
    }

    @Test func systemAudioFailureFallsBackToMicOnly() async throws {
        let context = try makeInMemoryContext()
        let coordinator = CaptureCoordinator(
            transcription: MockTranscriptionService(phrases: ["hello"], interval: .milliseconds(5)),
            systemTranscription: FailingTranscriptionService(),
            model: FakeReviewModel()
        )
        await coordinator.start(context: context)
        #expect(coordinator.state == .listening)
        #expect(coordinator.systemAudioActive == false)
        #expect(coordinator.errorMessage != nil)
        await coordinator.stop()
    }

    @Test func pauseAndResumeContinueTheSameNote() async throws {
        let context = try makeInMemoryContext()
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub())]
        let coordinator = CaptureCoordinator(
            transcription: MockTranscriptionService(phrases: ["one", "two", "three"], interval: .milliseconds(5)),
            systemTranscription: FailingTranscriptionService(),
            model: model
        )
        coordinator.captureSystemAudio = false
        await coordinator.start(context: context)
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.pause()
        #expect(coordinator.state == .paused)
        await coordinator.resume()
        #expect(coordinator.state == .listening)
        await coordinator.stop()
        let notes = try context.fetch(FetchDescriptor<ReviewNote>())
        #expect(notes.count == 1)
    }
}
```

Delete `RevueAITests/SmokeTests.swift` (its assertion now lives in RollingTranscriptTests).

- [ ] **Step 3: Run the tests**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **` — these tests document existing behavior, so all should pass without production changes. If one fails, the test's expectation is wrong (or it exposed a real bug — stop and report it), fix the test, re-run.

- [ ] **Step 4: Commit**

```bash
git add RevueAITests
git commit -m "test: baseline coverage for pipeline seams with fakes"
```

---

### Task 3: Watermark peek/commit — failed live extractions retry

**Files:**
- Modify: `MyApp/Capture/RollingTranscript.swift`
- Modify: `MyApp/CaptureCoordinator.swift` (the `runLiveExtraction` method)
- Modify: `RevueAITests/RollingTranscriptTests.swift`
- Modify: `RevueAITests/CaptureCoordinatorTests.swift` (add one test)

**Interfaces:**
- Consumes: `RollingTranscript.segments`, `lastExtractedIndex`.
- Produces: `func peekNewSegments() -> [AudioSegment]`, `func commitExtracted(count: Int)` — replacing `drainNewSegments()`, which is deleted. Task 9 also relies on `peekNewSegments`/`commitExtracted` staying exactly these names.

- [ ] **Step 1: Rewrite the transcript tests for peek/commit**

In `RevueAITests/RollingTranscriptTests.swift`, replace the `drainReturnsOnlyFreshSegmentsOnce` and `clearResetsEverything` tests with:

```swift
    @Test func peekDoesNotAdvanceTheWatermark() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        #expect(transcript.peekNewSegments().map(\.text) == ["one"])
        #expect(transcript.peekNewSegments().map(\.text) == ["one"])
    }

    @Test func commitAdvancesByCount() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        transcript.append(seg("two"))
        let fresh = transcript.peekNewSegments()
        transcript.commitExtracted(count: fresh.count)
        #expect(transcript.peekNewSegments().isEmpty)
        transcript.append(seg("three"))
        #expect(transcript.peekNewSegments().map(\.text) == ["three"])
    }

    @Test func failedExtractionKeepsSegmentsQueued() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        _ = transcript.peekNewSegments()   // extraction ran but failed: no commit
        transcript.append(seg("two"))
        #expect(transcript.peekNewSegments().map(\.text) == ["one", "two"])
    }

    @Test func segmentsArrivingDuringExtractionStayQueued() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        let fresh = transcript.peekNewSegments()
        transcript.append(seg("two"))          // arrives while the model call is in flight
        transcript.commitExtracted(count: fresh.count)
        #expect(transcript.peekNewSegments().map(\.text) == ["two"])
    }

    @Test func commitNeverOverruns() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        transcript.commitExtracted(count: 99)
        #expect(transcript.peekNewSegments().isEmpty)
        transcript.append(seg("two"))
        #expect(transcript.peekNewSegments().map(\.text) == ["two"])
    }

    @Test func clearResetsEverything() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        _ = transcript.peekNewSegments()
        transcript.clear()
        #expect(transcript.isEmpty)
        #expect(transcript.peekNewSegments().isEmpty)
    }
```

In `RevueAITests/CaptureCoordinatorTests.swift`, add:

```swift
    @Test func failedLiveExtractionRetriesTheSameChunk() async throws {
        let context = try makeInMemoryContext()
        let model = FakeReviewModel()
        model.extractResults = [
            .failure(FakeModelError()),
            .success(.empty),
        ]
        let coordinator = CaptureCoordinator(
            transcription: MockTranscriptionService(phrases: ["hello there"], interval: .milliseconds(5)),
            systemTranscription: FailingTranscriptionService(),
            model: model
        )
        coordinator.captureSystemAudio = false
        await coordinator.start(context: context)
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.pause()    // pause() runs a live extraction — this one fails
        // Stop directly from paused (resuming would make the mock replay its
        // phrases and change the chunk). stop() runs another extraction —
        // the same chunk must be re-sent because the failure didn't commit.
        await coordinator.stop()
        #expect(model.extractCalls.count == 2)
        #expect(model.extractCalls[0].chunk == model.extractCalls[1].chunk)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: BUILD FAILURE — `peekNewSegments`/`commitExtracted` don't exist yet.

- [ ] **Step 3: Implement peek/commit**

In `MyApp/Capture/RollingTranscript.swift`, replace `drainNewSegments()` with:

```swift
    /// Segments captured since the last committed extraction. Does NOT advance
    /// the watermark — call `commitExtracted(count:)` after the model call
    /// succeeds, so a failed extraction leaves the chunk queued for retry.
    func peekNewSegments() -> [AudioSegment] {
        guard lastExtractedIndex < segments.count else { return [] }
        return Array(segments[lastExtractedIndex...])
    }

    /// Marks `count` peeked segments as extracted. Counting (rather than
    /// draining) means segments that arrived while the model call was in
    /// flight stay queued.
    func commitExtracted(count: Int) {
        lastExtractedIndex = min(lastExtractedIndex + count, segments.count)
    }
```

In `MyApp/CaptureCoordinator.swift`, replace the body of `runLiveExtraction()`:

```swift
    private func runLiveExtraction() async {
        guard modelAvailable, let note = currentNote, let context = modelContext else { return }
        let fresh = transcript.peekNewSegments()
        guard !fresh.isEmpty else { return }
        let chunk = fresh
            .map { "[\($0.speakerHint.rawValue)] \($0.text)" }
            .joined(separator: "\n")
        do {
            try await liveExtractor.extractAndCheckpoint(chunk: chunk, into: note, context: context)
            transcript.commitExtracted(count: fresh.count)
            livePoints = note.sortedActionItems.map(\.oneLiner)
                + note.sortedOpenQuestions.map { "? \($0.text)" }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MyApp/Capture/RollingTranscript.swift MyApp/CaptureCoordinator.swift RevueAITests
git commit -m "fix: failed live extractions leave the chunk queued for retry"
```

---

### Task 4: Cap the known-points list sent to the live pass

**Files:**
- Modify: `MyApp/AI/LiveExtractor.swift`
- Modify: `RevueAITests/LiveExtractorTests.swift`

**Interfaces:**
- Consumes: `ReviewNote.actionItems`, `.openQuestions` (raw optionals; capture `order` for recency).
- Produces: `static func knownPointsSummary(for note: ReviewNote, limit: Int? = nil) -> String` and `static let liveKnownPointsLimit = 25`. `FinalPolisher` keeps calling it with no limit (sees everything).

- [ ] **Step 1: Write the failing tests**

Add to `RevueAITests/LiveExtractorTests.swift`:

```swift
    @Test func knownPointsAreCappedForTheLivePass() throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        for i in 0..<30 {
            let item = ActionItem(oneLiner: "Item \(i)", order: i)
            item.note = note
            context.insert(item)
        }
        let capped = LiveExtractor.knownPointsSummary(for: note, limit: 25)
        let lines = capped.split(separator: "\n")
        #expect(lines.count == 26)
        #expect(lines.first == "(+5 earlier points)")
        #expect(lines.last == "- Item 29")

        let uncapped = LiveExtractor.knownPointsSummary(for: note)
        #expect(uncapped.split(separator: "\n").count == 30)
    }

    @Test func livePassSendsCappedKnownPoints() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        for i in 0..<30 {
            let item = ActionItem(oneLiner: "Item \(i)", order: i)
            item.note = note
            context.insert(item)
        }
        let model = FakeReviewModel()
        let extractor = LiveExtractor(model: model)
        try await extractor.extractAndCheckpoint(chunk: "[presenter] talk", into: note, context: context)
        let known = try #require(model.extractCalls.first?.knownPoints)
        #expect(known.contains("(+5 earlier points)"))
        #expect(!known.contains("- Item 0\n"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: BUILD FAILURE — `knownPointsSummary(for:limit:)` doesn't exist.

- [ ] **Step 3: Implement the cap**

In `MyApp/AI/LiveExtractor.swift`, add the constant near the top of the class and replace `knownPointsSummary`:

```swift
    /// Most recent points sent to the live pass — bounds context on long meetings.
    static let liveKnownPointsLimit = 25
```

```swift
    /// A compact list of the points already extracted, in capture order. Pass
    /// `limit` to keep only the most recent entries (live pass); the final
    /// pass omits it and sees everything.
    static func knownPointsSummary(for note: ReviewNote, limit: Int? = nil) -> String {
        let items = (note.actionItems ?? [])
            .sorted { $0.order < $1.order }
            .map { "- \($0.oneLiner)" }
        let questions = (note.openQuestions ?? [])
            .sorted { $0.order < $1.order }
            .map { "? \($0.text)" }
        var entries = items + questions
        if let limit, entries.count > limit {
            let omitted = entries.count - limit
            entries = ["(+\(omitted) earlier points)"] + entries.suffix(limit)
        }
        return entries.joined(separator: "\n")
    }
```

In `extractAndCheckpoint`, change the `known` line to:

```swift
        let known = Self.knownPointsSummary(for: note, limit: Self.liveKnownPointsLimit)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MyApp/AI/LiveExtractor.swift RevueAITests/LiveExtractorTests.swift
git commit -m "feat: cap known points sent to the live pass on long meetings"
```

---

### Task 5: TranscriptWindower

**Files:**
- Create: `MyApp/Capture/TranscriptWindower.swift`
- Create: `RevueAITests/TranscriptWindowerTests.swift`

**Interfaces:**
- Consumes: `AudioSegment` (`speakerHint.rawValue`, `text`), `Equatable`.
- Produces (Task 6 relies on these exact names): `TranscriptWindower.windows(for: [AudioSegment], tokenBudget: Int) -> [[AudioSegment]]`, `TranscriptWindower.estimatedTokens(_ segments: [AudioSegment]) -> Int`, `TranscriptWindower.overlapSegments` (= 2).

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/TranscriptWindowerTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct TranscriptWindowerTests {
    private func seg(_ text: String) -> AudioSegment {
        AudioSegment(speakerHint: .reviewer, text: text)
    }

    /// 60 segments of ~40 characters each ≈ 600+ estimated tokens.
    /// Stored (not computed) so repeated accesses compare equal — AudioSegment's
    /// Equatable includes its UUID, so a computed property would mint fresh
    /// non-equal segments on every access.
    private let longTranscript: [AudioSegment] = (0..<60).map {
        AudioSegment(speakerHint: .reviewer, text: "Segment number \($0) with some padding text")
    }

    @Test func emptyInputYieldsNoWindows() {
        #expect(TranscriptWindower.windows(for: [], tokenBudget: 100).isEmpty)
    }

    @Test func transcriptUnderBudgetIsOneWindow() {
        let segments = [seg("short"), seg("also short")]
        let windows = TranscriptWindower.windows(for: segments, tokenBudget: 1000)
        #expect(windows.count == 1)
        #expect(windows[0] == segments)
    }

    @Test func windowsRespectTheBudget() {
        let windows = TranscriptWindower.windows(for: longTranscript, tokenBudget: 100)
        #expect(windows.count > 1)
        for window in windows {
            #expect(TranscriptWindower.estimatedTokens(window) <= 100)
        }
    }

    @Test func consecutiveWindowsOverlap() {
        let windows = TranscriptWindower.windows(for: longTranscript, tokenBudget: 100)
        for i in 1..<windows.count {
            let tail = Array(windows[i - 1].suffix(TranscriptWindower.overlapSegments))
            let head = Array(windows[i].prefix(TranscriptWindower.overlapSegments))
            #expect(tail == head)
        }
    }

    @Test func noSegmentIsLostOrReordered() {
        let windows = TranscriptWindower.windows(for: longTranscript, tokenBudget: 100)
        var reconstructed = windows[0]
        for window in windows.dropFirst() {
            reconstructed += window.dropFirst(TranscriptWindower.overlapSegments)
        }
        #expect(reconstructed == longTranscript)
    }

    @Test func oversizedSegmentIsNeverDropped() {
        let huge = seg(String(repeating: "x", count: 2000))
        let windows = TranscriptWindower.windows(for: [seg("small"), huge, seg("small too")], tokenBudget: 50)
        #expect(windows.flatMap { $0 }.contains(huge))
    }

    @Test func trailingSegmentAfterOversizedWindowIsNotDropped() {
        let huge = seg(String(repeating: "x", count: 2000))
        let tail = seg("tail")
        let windows = TranscriptWindower.windows(for: [huge, tail], tokenBudget: 50)
        #expect(windows.flatMap { $0 }.contains(tail))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: BUILD FAILURE — `TranscriptWindower` doesn't exist.

- [ ] **Step 3: Implement the windower**

Create `MyApp/Capture/TranscriptWindower.swift`:

```swift
import Foundation

/// Splits a transcript into windows that each fit a token budget, with a small
/// segment overlap so points spanning a boundary aren't lost. Pure and
/// stateless. Token counts use a ~4 characters/token heuristic — deliberately
/// rough; budgets are chosen with headroom.
enum TranscriptWindower {
    /// Trailing segments repeated at the start of the next window.
    static let overlapSegments = 2
    static let charactersPerToken = 4

    /// "[hint] text\n" — brackets, space, newline ≈ 4 extra characters.
    private static func characters(_ segment: AudioSegment) -> Int {
        segment.text.count + segment.speakerHint.rawValue.count + 4
    }

    static func estimatedTokens(_ segments: [AudioSegment]) -> Int {
        segments.reduce(0) { $0 + characters($1) } / charactersPerToken
    }

    /// Every input segment lands in at least one window, in order. A segment
    /// larger than the whole budget is still emitted (its windows simply
    /// exceed the budget, and it can repeat across a few consecutive
    /// overlaps — wasteful but never lossy).
    ///
    /// The accumulator tracks characters (not per-segment floored tokens) so
    /// the budget check is exactly `estimatedTokens(window) <= tokenBudget` —
    /// summing floored per-segment costs would under-count and let windows
    /// exceed the budget by rounding drift. `carriedCount` tracks how much of
    /// `current` is overlap carried from the previous window, so the final
    /// flush emits exactly when there is new content — a `count >
    /// overlapSegments` proxy would drop a trailing segment after an
    /// undersized (single-segment) window.
    static func windows(for segments: [AudioSegment], tokenBudget: Int) -> [[AudioSegment]] {
        guard !segments.isEmpty else { return [] }
        guard estimatedTokens(segments) > tokenBudget else { return [segments] }

        var result: [[AudioSegment]] = []
        var current: [AudioSegment] = []
        var currentCharacters = 0
        var carriedCount = 0
        for segment in segments {
            let cost = characters(segment)
            if !current.isEmpty, (currentCharacters + cost) / charactersPerToken > tokenBudget {
                result.append(current)
                let overlap = Array(current.suffix(overlapSegments))
                current = overlap
                carriedCount = overlap.count
                currentCharacters = overlap.reduce(0) { $0 + characters($1) }
            }
            current.append(segment)
            currentCharacters += cost
        }
        if current.count > carriedCount || result.isEmpty {
            result.append(current)
        }
        return result
    }
}
```

Note the final guard: if the leftover `current` is nothing but the overlap copied from the previous window, don't emit a duplicate window.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`. Note: `windowsRespectTheBudget` may legitimately fail for a window holding one oversized segment — the fixture's segments are ~11 tokens each against a 100-token budget, so this doesn't arise here.

- [ ] **Step 5: Commit**

```bash
git add MyApp/Capture/TranscriptWindower.swift RevueAITests/TranscriptWindowerTests.swift
git commit -m "feat: add TranscriptWindower for budgeted transcript splitting"
```

---

### Task 6: Backend token budgets + map-reduce final pass

**Files:**
- Modify: `MyApp/AI/ReviewLanguageModel.swift` (protocol + both backends)
- Modify: `MyApp/AI/FinalPolisher.swift` (new signature + windowed path)
- Modify: `MyApp/CaptureCoordinator.swift` (the `stop()` method)
- Modify: `RevueAITests/Support/FakeReviewModel.swift`
- Modify: `RevueAITests/FinalPolisherTests.swift`

**Interfaces:**
- Consumes: `TranscriptWindower.windows(for:tokenBudget:)`, `estimatedTokens(_:)` from Task 5.
- Produces: `ReviewLanguageModel.contextTokenBudget: Int { get }` (on-device 3000, PCC 24000); `FinalPolisher.polish(note:segments:context:)` (replaces the `transcript: String` variant); `FinalPolisher.transcriptText(for: [AudioSegment]) -> String`; `PolishError.allWindowsFailed`.

- [ ] **Step 1: Update the fake and write the failing tests**

In `RevueAITests/Support/FakeReviewModel.swift`, add inside `FakeReviewModel`:

```swift
    var contextTokenBudget = 3000
```

In `RevueAITests/FinalPolisherTests.swift`, replace the whole file with:

```swift
import Foundation
import Testing
@testable import RevueAI

struct FinalPolisherTests {
    private func seg(_ text: String) -> AudioSegment {
        AudioSegment(speakerHint: .presenter, text: text)
    }

    /// 60 segments ≈ 600+ estimated tokens — several windows at budget 100.
    /// Stored so repeated accesses yield the identical (Equatable-equal) array.
    private let longTranscript: [AudioSegment] = (0..<60).map {
        AudioSegment(speakerHint: .presenter, text: "Segment number \($0) with some padding text")
    }

    @Test func successAppliesSummaryVerdictAndItems() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T", status: .capturing)
        context.insert(note)
        let stale = ActionItem(oneLiner: "Stale live point", order: 0)
        stale.note = note
        context.insert(stale)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(
            summary: "Reviewed the upload path.",
            verdict: .approved,
            actionItems: [.stub("Add retry logic to the upload path")]
        ))]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [seg("hello")], context: context)
        #expect(note.summary == "Reviewed the upload path.")
        #expect(note.verdict == .approved)
        #expect(note.status == .processedOnDevice)
        #expect(note.sortedActionItems.map(\.oneLiner) == ["Add retry logic to the upload path"])
    }

    @Test func failureKeepsLivePointsAndMarksOnDevice() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T", status: .capturing)
        context.insert(note)
        let item = ActionItem(oneLiner: "Fix retry logic", order: 0)
        item.note = note
        context.insert(item)
        let model = FakeReviewModel()
        model.polishResults = [.failure(FakeModelError())]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [seg("hello")], context: context)
        #expect(note.status == .processedOnDevice)
        #expect(note.sortedActionItems.map(\.oneLiner) == ["Fix retry logic"])
    }

    @Test func nearDuplicateItemsAreMerged() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(actionItems: [
            .stub("Add retry logic to the upload path"),
            .stub("Add retry logic to upload path"),
        ]))]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [seg("hello")], context: context)
        #expect(note.sortedActionItems.count == 1)
    }

    @Test func shortTranscriptUsesSingleCall() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub())]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [seg("hello")], context: context)
        #expect(model.polishCalls.count == 1)
        #expect(model.extractCalls.isEmpty)
        #expect(model.polishCalls.first?.transcript == "[presenter] hello")
    }

    @Test func longTranscriptMapReduces() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let model = FakeReviewModel()
        model.contextTokenBudget = 100
        let windowCount = TranscriptWindower.windows(for: longTranscript, tokenBudget: 100).count
        model.extractResults = (0..<windowCount).map { i in
            .success(ExtractedPoints(
                actionItems: [ActionItemCandidate(
                    oneLiner: "Point from window \(i)",
                    attribution: "Reviewer",
                    supportingQuote: ""
                )],
                decisions: [],
                openQuestions: []
            ))
        }
        model.polishResults = [.success(.stub())]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: longTranscript, context: context)
        #expect(model.extractCalls.count == windowCount)
        #expect(model.polishCalls.count == 1)
        let reduceInput = try #require(model.polishCalls.first?.transcript)
        #expect(reduceInput.contains("PRE-EXTRACTED"))
        #expect(reduceInput.contains("Point from window 0"))
        #expect(reduceInput.contains("Point from window \(windowCount - 1)"))
    }

    @Test func failedWindowIsSkippedNotFatal() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let model = FakeReviewModel()
        model.contextTokenBudget = 100
        let windowCount = TranscriptWindower.windows(for: longTranscript, tokenBudget: 100).count
        model.extractResults = [.failure(FakeModelError())] + (1..<windowCount).map { i in
            .success(ExtractedPoints(
                actionItems: [ActionItemCandidate(oneLiner: "Point \(i)", attribution: "R", supportingQuote: "")],
                decisions: [],
                openQuestions: []
            ))
        }
        model.polishResults = [.success(.stub())]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: longTranscript, context: context)
        #expect(model.polishCalls.count == 1)
        #expect(note.status == .processedOnDevice)
    }

    @Test func allWindowsFailingKeepsLivePoints() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let item = ActionItem(oneLiner: "Checkpointed point", order: 0)
        item.note = note
        context.insert(item)
        let model = FakeReviewModel()
        model.contextTokenBudget = 100
        let windowCount = TranscriptWindower.windows(for: longTranscript, tokenBudget: 100).count
        model.extractResults = (0..<windowCount).map { _ in .failure(FakeModelError()) }
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: longTranscript, context: context)
        #expect(model.polishCalls.isEmpty)
        #expect(note.status == .processedOnDevice)
        #expect(note.sortedActionItems.map(\.oneLiner) == ["Checkpointed point"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: BUILD FAILURE — `contextTokenBudget` not in protocol, `polish(note:segments:context:)` doesn't exist.

- [ ] **Step 3: Implement budgets and the map-reduce path**

In `MyApp/AI/ReviewLanguageModel.swift`:

Add to the protocol, after `isAvailable`:

```swift
    /// Approximate prompt-token budget for a single request to this backend,
    /// with headroom for instructions and output. Drives transcript windowing.
    var contextTokenBudget: Int { get }
```

Add to `OnDeviceReviewModel`:

```swift
    var contextTokenBudget: Int { 3000 }
```

Add to `PrivateCloudReviewModel`:

```swift
    var contextTokenBudget: Int { 24000 }
```

In `MyApp/AI/FinalPolisher.swift`, add above the class:

```swift
enum PolishError: Error {
    case allWindowsFailed
}
```

Replace the `polish` method and add the helpers (keep `apply`, `normalize`, `similar` unchanged):

```swift
    func polish(note: ReviewNote, segments: [AudioSegment], context: ModelContext) async {
        note.status = .processing
        try? context.save()

        let livePoints = LiveExtractor.knownPointsSummary(for: note)
        do {
            let result: PolishedReview
            if TranscriptWindower.estimatedTokens(segments) <= model.contextTokenBudget {
                result = try await model.polish(
                    transcript: Self.transcriptText(for: segments),
                    livePoints: livePoints
                )
            } else {
                result = try await windowedPolish(segments: segments, livePoints: livePoints)
            }
            apply(result, to: note, context: context)
            note.status = (model is PrivateCloudReviewModel) ? .polished : .processedOnDevice
        } catch {
            // Preserve whatever live points were already checkpointed.
            note.status = .processedOnDevice
        }
        try? context.save()
    }

    static func transcriptText(for segments: [AudioSegment]) -> String {
        segments
            .map { "[\($0.speakerHint.rawValue)] \($0.text)" }
            .joined(separator: "\n")
    }

    /// Map-reduce fallback for transcripts exceeding the backend's budget:
    /// extract enriched candidates per window (seeded with the live points so
    /// windows don't re-report known items), then consolidate the compact
    /// candidate list in one polish call.
    private func windowedPolish(segments: [AudioSegment], livePoints: String) async throws -> PolishedReview {
        let windows = TranscriptWindower.windows(for: segments, tokenBudget: model.contextTokenBudget)
        var known = livePoints
        var failures = 0
        for window in windows {
            do {
                let points = try await model.extractPoints(
                    fromChunk: Self.transcriptText(for: window),
                    knownPoints: known
                )
                known = Self.appendingCandidates(points, to: known)
            } catch {
                failures += 1
            }
        }
        guard failures < windows.count else { throw PolishError.allWindowsFailed }
        let digest = """
        POINTS PRE-EXTRACTED FROM THE FULL MEETING (the raw transcript was too \
        long to include; consolidate these):
        \(known.isEmpty ? "(none)" : known)
        """
        return try await model.polish(transcript: digest, livePoints: "")
    }

    private static func appendingCandidates(_ points: ExtractedPoints, to known: String) -> String {
        var lines = known.isEmpty ? [] : [known]
        for item in points.actionItems {
            var line = "- \(item.oneLiner) (raised by \(item.attribution))"
            if !item.supportingQuote.isEmpty { line += " — quote: \"\(item.supportingQuote)\"" }
            lines.append(line)
        }
        for decision in points.decisions {
            lines.append("• Decision: \(decision.statement) (\(decision.attribution))")
        }
        for question in points.openQuestions {
            lines.append("? \(question.question) (asked by \(question.attribution))")
        }
        return lines.joined(separator: "\n")
    }
```

In `MyApp/CaptureCoordinator.swift` `stop()`, replace the transcript/polish block:

```swift
        if let note = currentNote {
            note.durationSeconds = Double(accumulatedSeconds)
            if transcript.isEmpty {
                note.summary = "No speech was captured in this session."
                note.status = .processedOnDevice
                try? context.save()
            } else if modelAvailable {
                await finalPolisher.polish(note: note, segments: transcript.segments, context: context)
            } else {
                note.summary = "Captured, but Apple Intelligence is off — turn it on to summarize."
                note.status = .processedOnDevice
                try? context.save()
            }
```

(The `lastTitle`/`lastSummary`/`livePoints` lines after this block stay as they are.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MyApp RevueAITests
git commit -m "feat: map-reduce final pass for transcripts beyond the context budget"
```

---

### Task 7: First-class Decision model, end to end

**Files:**
- Create: `MyApp/Models/Decision.swift`
- Modify: `MyApp/Models/ReviewNote.swift`
- Modify: `MyApp/RevueAIApp.swift` (schema list)
- Modify: `MyApp/AI/ExtractedPoint.swift` (`PolishedReview`)
- Modify: `MyApp/AI/LiveExtractor.swift`
- Modify: `MyApp/AI/FinalPolisher.swift` (`apply`)
- Modify: `MyApp/AI/MarkdownExporter.swift`
- Modify: `MyApp/CaptureCoordinator.swift` (livePoints lines, 2 places)
- Modify: `MyApp/Views/NoteDetailView.swift`
- Modify: `RevueAITests/Support/TestSupport.swift` (schema + stub)
- Modify: `RevueAITests/LiveExtractorTests.swift`, `RevueAITests/FinalPolisherTests.swift`, `RevueAITests/MarkdownExporterTests.swift`

**Interfaces:**
- Consumes: `DecisionCandidate` (`statement`, `attribution`) — already in the live schema.
- Produces: `@Model final class Decision` (`statement`, `attribution`, `order`, `note`); `ReviewNote.decisions: [Decision]?` + `sortedDecisions`; `PolishedReview.decisions: [DecisionCandidate]` (declared AFTER `openQuestions`, so the memberwise init order is `summary, verdict, actionItems, openQuestions, decisions`).

- [ ] **Step 1: Write the failing tests**

Add to `RevueAITests/LiveExtractorTests.swift`:

```swift
    @Test func persistsDecisions() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let model = FakeReviewModel()
        model.extractResults = [.success(ExtractedPoints(
            actionItems: [],
            decisions: [DecisionCandidate(statement: "Use SwiftData over Core Data", attribution: "presenter")],
            openQuestions: []
        ))]
        let extractor = LiveExtractor(model: model)
        try await extractor.extractAndCheckpoint(chunk: "[presenter] let's use SwiftData", into: note, context: context)
        #expect(note.sortedDecisions.map(\.statement) == ["Use SwiftData over Core Data"])
        #expect(note.sortedDecisions.first?.attribution == "presenter")
    }
```

Add to `RevueAITests/FinalPolisherTests.swift`:

```swift
    @Test func appliesConsolidatedDecisions() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let stale = Decision(statement: "Old live decision", order: 0)
        stale.note = note
        context.insert(stale)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(decisions: [
            DecisionCandidate(statement: "Ship behind a feature flag", attribution: "Reviewer 1"),
        ]))]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [seg("hello")], context: context)
        #expect(note.sortedDecisions.map(\.statement) == ["Ship behind a feature flag"])
    }
```

In `RevueAITests/MarkdownExporterTests.swift`, add inside `rendersHeaderItemsAndQuestions` before the `let markdown` line:

```swift
        let decision = Decision(statement: "Ship behind a feature flag", attribution: "Reviewer 1", order: 0)
        decision.note = note
        context.insert(decision)
```

and add these assertions:

```swift
        #expect(markdown.contains("## Decisions"))
        #expect(markdown.contains("- Ship behind a feature flag"))
```

In `RevueAITests/Support/TestSupport.swift`:
- Add `Decision.self,` to the `Schema([...])` array (after `OpenQuestion.self`).
- In `PolishedReview.stub`, add a final parameter `decisions: [DecisionCandidate] = []` and pass `decisions: decisions` as the LAST argument of the `PolishedReview(...)` call.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: BUILD FAILURE — `Decision` doesn't exist.

- [ ] **Step 3: Implement Decision end to end**

Create `MyApp/Models/Decision.swift`:

```swift
import Foundation
import SwiftData

/// A decision made during a review, with attribution. Extracted live and
/// consolidated by the final pass, like action items and open questions.
@Model
final class Decision {
    var id: UUID = UUID()

    /// A concise statement of what was decided.
    var statement: String = ""

    /// Session-scoped speaker label of who made or drove the decision.
    var attribution: String = ""

    /// Capture order, used for stable sorting.
    var order: Int = 0

    /// Inverse of `ReviewNote.decisions`. Optional for CloudKit.
    var note: ReviewNote?

    init(
        id: UUID = UUID(),
        statement: String = "",
        attribution: String = "",
        order: Int = 0
    ) {
        self.id = id
        self.statement = statement
        self.attribution = attribution
        self.order = order
    }
}
```

In `MyApp/Models/ReviewNote.swift`, after the `openQuestions` relationship add:

```swift
    @Relationship(deleteRule: .cascade, inverse: \Decision.note)
    var decisions: [Decision]? = []
```

and after `sortedOpenQuestions` add:

```swift
    /// Decisions sorted by their capture order.
    var sortedDecisions: [Decision] {
        (decisions ?? []).sorted { $0.order < $1.order }
    }
```

In `MyApp/RevueAIApp.swift`, add `Decision.self,` to the `Schema([...])` array (after `OpenQuestion.self`).

In `MyApp/AI/ExtractedPoint.swift`, add to `PolishedReview` AFTER the `openQuestions` property:

```swift
    @Guide(description: "The key decisions that were made, consolidated and de-duplicated.")
    var decisions: [DecisionCandidate]
```

In `MyApp/AI/LiveExtractor.swift`, in `extractAndCheckpoint` after the open-questions loop, add:

```swift
        var decisionOrder = note.decisions?.count ?? 0
        for candidate in points.decisions {
            let decision = Decision(
                statement: candidate.statement,
                attribution: candidate.attribution,
                order: decisionOrder
            )
            decision.note = note
            context.insert(decision)
            decisionOrder += 1
        }
```

Also in `knownPointsSummary`, include decisions so the live model doesn't re-extract them — change the `entries` assembly to:

```swift
        let decisions = (note.decisions ?? [])
            .sorted { $0.order < $1.order }
            .map { "• \($0.statement)" }
        var entries = items + decisions + questions
```

In `MyApp/AI/FinalPolisher.swift` `apply(_:to:context:)`, add `for existing in note.decisions ?? [] { context.delete(existing) }` next to the other two delete loops, and after the questions loop add:

```swift
        var seenDecisions: [String] = []
        var decisionOrder = 0
        for decision in result.decisions {
            let key = Self.normalize(decision.statement)
            guard !key.isEmpty, !seenDecisions.contains(where: { Self.similar($0, key) }) else { continue }
            seenDecisions.append(key)
            let record = Decision(
                statement: decision.statement,
                attribution: decision.attribution,
                order: decisionOrder
            )
            record.note = note
            context.insert(record)
            decisionOrder += 1
        }
```

In `MyApp/AI/MarkdownExporter.swift`, after the summary block and before the action-items block, add:

```swift
        let decisions = note.sortedDecisions
        if !decisions.isEmpty {
            lines.append("## Decisions")
            lines.append("")
            for decision in decisions {
                var line = "- \(decision.statement)"
                if !decision.attribution.isEmpty { line += " _(\(decision.attribution))_" }
                lines.append(line)
            }
            lines.append("")
        }
```

In `MyApp/CaptureCoordinator.swift`, both places that build `livePoints` (in `stop()` and `runLiveExtraction()`) become:

```swift
            livePoints = note.sortedActionItems.map(\.oneLiner)
                + note.sortedDecisions.map { "✓ \($0.statement)" }
                + note.sortedOpenQuestions.map { "? \($0.text)" }
```

In `MyApp/Views/NoteDetailView.swift`, add `decisionsStrip` to the body right after `summaryStrip`, and add the view below `summaryStrip`'s definition:

```swift
    @ViewBuilder
    private var decisionsStrip: some View {
        let decisions = note.sortedDecisions
        if !decisions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Decisions", systemImage: "checkmark.seal")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                ForEach(decisions) { decision in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(decision.statement)
                    }
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MyApp RevueAITests
git commit -m "feat: persist decisions end to end (live pass, polish, export, detail view)"
```

---

### Task 8: Speaker roster refinement in the final pass

**Files:**
- Modify: `MyApp/AI/ExtractedPoint.swift` (`SpeakerCandidate`, `PolishedReview.speakers`)
- Modify: `MyApp/AI/ReviewLanguageModel.swift` (`polishInstructions`)
- Modify: `MyApp/AI/FinalPolisher.swift` (`apply`)
- Modify: `RevueAITests/Support/TestSupport.swift` (stub)
- Modify: `RevueAITests/FinalPolisherTests.swift`

**Interfaces:**
- Consumes: existing `Speaker` model (`label: String`, `isPresenter: Bool`, `note: ReviewNote?`), `ReviewNote.speakers: [Speaker]?`.
- Produces: `@Generable struct SpeakerCandidate` (`label: String`, `isPresenter: Bool`); `PolishedReview.speakers: [SpeakerCandidate]` (declared AFTER `decisions` — memberwise init order becomes `summary, verdict, actionItems, openQuestions, decisions, speakers`).

- [ ] **Step 1: Write the failing test**

Add to `RevueAITests/FinalPolisherTests.swift`:

```swift
    @Test func populatesTheSpeakerRoster() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(speakers: [
            SpeakerCandidate(label: "You", isPresenter: true),
            SpeakerCandidate(label: "Priya", isPresenter: false),
            SpeakerCandidate(label: "Priya", isPresenter: false),   // duplicate — dropped
        ]))]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [seg("hello")], context: context)
        let labels = (note.speakers ?? []).map(\.label).sorted()
        #expect(labels == ["Priya", "You"])
        #expect((note.speakers ?? []).first { $0.label == "You" }?.isPresenter == true)
    }
```

In `RevueAITests/Support/TestSupport.swift`, add a final parameter to `PolishedReview.stub`: `speakers: [SpeakerCandidate] = []`, passed as the LAST argument of the `PolishedReview(...)` call (after `decisions`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: BUILD FAILURE — `SpeakerCandidate` doesn't exist.

- [ ] **Step 3: Implement the roster**

In `MyApp/AI/ExtractedPoint.swift`, add near the other candidate types:

```swift
@Generable
struct SpeakerCandidate: Equatable {
    @Guide(description: "The speaker's display label: a real name heard in the meeting if any, otherwise 'You' for the presenter or 'Reviewer 1', 'Reviewer 2', …")
    var label: String

    @Guide(description: "True if this speaker is the presenter (the person whose microphone was captured).")
    var isPresenter: Bool
}
```

Add to `PolishedReview` AFTER the `decisions` property:

```swift
    @Guide(description: "The distinct speakers in the meeting, one entry each.")
    var speakers: [SpeakerCandidate]
```

In `MyApp/AI/ReviewLanguageModel.swift`, add this bullet to `polishInstructions` before the final "Be faithful" line:

```
    • List the distinct speakers: use a real name when one is heard in the \
    transcript; otherwise 'You' for the presenter and 'Reviewer 1', \
    'Reviewer 2' for others. Attribute every action item, decision, and open \
    question using exactly these labels. \
```

In `MyApp/AI/FinalPolisher.swift` `apply(_:to:context:)`, add `for existing in note.speakers ?? [] { context.delete(existing) }` next to the other delete loops, and at the end of the method add:

```swift
        var seenLabels: [String] = []
        for candidate in result.speakers {
            let label = candidate.label.trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, !seenLabels.contains(label) else { continue }
            seenLabels.append(label)
            let speaker = Speaker(label: label, isPresenter: candidate.isPresenter)
            speaker.note = note
            context.insert(speaker)
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MyApp RevueAITests
git commit -m "feat: final pass builds a named speaker roster for attributions"
```

---

### Task 9: Prewarm + hybrid extraction cadence

**Files:**
- Modify: `MyApp/AI/ReviewLanguageModel.swift` (protocol + default + on-device impl)
- Modify: `MyApp/CaptureCoordinator.swift`
- Modify: `MyApp/Capture/RollingTranscript.swift` (`pendingCount`)
- Modify: `RevueAITests/Support/FakeReviewModel.swift`
- Modify: `RevueAITests/CaptureCoordinatorTests.swift`, `RevueAITests/RollingTranscriptTests.swift`

**Interfaces:**
- Consumes: `peekNewSegments`/`commitExtracted` from Task 3.
- Produces: `ReviewLanguageModel.prewarm()` (default no-op); `RollingTranscript.pendingCount: Int`; `CaptureCoordinator.shouldExtract(pending:elapsedSinceLastRun:threshold:interval:) -> Bool` (nonisolated static).

- [ ] **Step 1: Write the failing tests**

In `RevueAITests/Support/FakeReviewModel.swift`, add inside `FakeReviewModel`:

```swift
    private(set) var prewarmCount = 0

    func prewarm() { prewarmCount += 1 }
```

Add to `RevueAITests/RollingTranscriptTests.swift`:

```swift
    @Test func pendingCountTracksUncommittedSegments() {
        let transcript = RollingTranscript()
        #expect(transcript.pendingCount == 0)
        transcript.append(seg("one"))
        transcript.append(seg("two"))
        #expect(transcript.pendingCount == 2)
        transcript.commitExtracted(count: 1)
        #expect(transcript.pendingCount == 1)
    }
```

Add to `RevueAITests/CaptureCoordinatorTests.swift`:

```swift
    @Test func startPrewarmsTheModel() async throws {
        let context = try makeInMemoryContext()
        let model = FakeReviewModel()
        let coordinator = CaptureCoordinator(
            transcription: MockTranscriptionService(phrases: [], interval: .milliseconds(5)),
            systemTranscription: FailingTranscriptionService(),
            model: model
        )
        coordinator.captureSystemAudio = false
        await coordinator.start(context: context)
        #expect(model.prewarmCount == 1)
        await coordinator.stop()
    }

    @Test func extractionTriggerLogic() {
        // Below threshold, interval not due → wait.
        #expect(!CaptureCoordinator.shouldExtract(
            pending: 3, elapsedSinceLastRun: .seconds(5), threshold: 6, interval: .seconds(20)))
        // Threshold reached → extract even if the interval isn't due.
        #expect(CaptureCoordinator.shouldExtract(
            pending: 6, elapsedSinceLastRun: .seconds(1), threshold: 6, interval: .seconds(20)))
        // Interval due with at least one pending → extract.
        #expect(CaptureCoordinator.shouldExtract(
            pending: 1, elapsedSinceLastRun: .seconds(20), threshold: 6, interval: .seconds(20)))
        // Nothing pending → never extract, no matter how long it's been.
        #expect(!CaptureCoordinator.shouldExtract(
            pending: 0, elapsedSinceLastRun: .seconds(120), threshold: 6, interval: .seconds(20)))
        // After a failed attempt the threshold shortcut is suppressed — a
        // stuck-high pending count must not hot-loop retries every tick.
        #expect(!CaptureCoordinator.shouldExtract(
            pending: 10, elapsedSinceLastRun: .seconds(2), threshold: 6, interval: .seconds(20),
            lastAttemptFailed: true))
        // Once the full interval elapses, a retry is allowed even after failure.
        #expect(CaptureCoordinator.shouldExtract(
            pending: 10, elapsedSinceLastRun: .seconds(20), threshold: 6, interval: .seconds(20),
            lastAttemptFailed: true))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: BUILD FAILURE — `prewarm` not in protocol, `pendingCount`/`shouldExtract` missing.

- [ ] **Step 3: Implement prewarm and the hybrid cadence**

In `MyApp/AI/ReviewLanguageModel.swift`:

Add to the protocol, after `contextTokenBudget`:

```swift
    /// Optional warm-up before the first live call (e.g. load the on-device
    /// model into memory). Fire-and-forget; default is a no-op.
    func prewarm()
```

Add below the protocol:

```swift
extension ReviewLanguageModel {
    func prewarm() {}
}
```

Add to `OnDeviceReviewModel`:

```swift
    func prewarm() {
        LanguageModelSession(instructions: ReviewPrompts.liveInstructions).prewarm()
    }
```

In `MyApp/Capture/RollingTranscript.swift`, add:

```swift
    /// Segments appended but not yet committed as extracted.
    var pendingCount: Int { segments.count - lastExtractedIndex }
```

In `MyApp/CaptureCoordinator.swift`:

Add a stored property next to the other dependencies, and assign it in `init` (from the existing `model` parameter):

```swift
    private let model: any ReviewLanguageModel
```

```swift
        self.model = model
```

Replace the timing constants:

```swift
    private let firstExtractionDelay: Duration = .seconds(12)
    private let extractionInterval: Duration = .seconds(20)
    private let extractionSegmentThreshold = 6
    private let cadenceTick: Duration = .seconds(2)
```

In `start(context:)`, after `modelContext = context`, add:

```swift
        model.prewarm()
```

Replace `startCadence()` and add the trigger helper:

```swift
    /// Hybrid trigger: a burst of new segments extracts immediately; otherwise
    /// the interval flushes whatever trickled in. Silence costs nothing.
    /// After a failed attempt the threshold shortcut is suppressed (failure
    /// leaves pending high, and without this the cadence would retry every
    /// tick); retries fall back to interval pacing.
    nonisolated static func shouldExtract(
        pending: Int,
        elapsedSinceLastRun: Duration,
        threshold: Int,
        interval: Duration,
        lastAttemptFailed: Bool = false
    ) -> Bool {
        guard pending > 0 else { return false }
        if lastAttemptFailed { return elapsedSinceLastRun >= interval }
        return pending >= threshold || elapsedSinceLastRun >= interval
    }

    private func startCadence() {
        cadenceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.firstExtractionDelay)
            var lastRun = ContinuousClock.now
            while !Task.isCancelled {
                if Self.shouldExtract(
                    pending: self.transcript.pendingCount,
                    elapsedSinceLastRun: ContinuousClock.now - lastRun,
                    threshold: self.extractionSegmentThreshold,
                    interval: self.extractionInterval,
                    lastAttemptFailed: self.lastExtractionFailed
                ) {
                    await self.runLiveExtraction()
                    lastRun = ContinuousClock.now
                }
                try? await Task.sleep(for: self.cadenceTick)
            }
        }
    }
```

Add a stored property next to the timing constants:

```swift
    /// Whether the most recent live-extraction attempt threw — suppresses the
    /// cadence's threshold shortcut so failures retry at interval pacing.
    private var lastExtractionFailed = false
```

Reset it in `start(context:)` alongside the other per-session state (`errorMessage = nil` block): `lastExtractionFailed = false`.

Set it in `runLiveExtraction()`: add `lastExtractionFailed = false` immediately after `transcript.commitExtracted(count: fresh.count)`, and `lastExtractionFailed = true` as the first line of the `catch` block.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MyApp RevueAITests
git commit -m "feat: prewarm the model on start and extract on segment bursts"
```

---

### Task 10: Shared PointDedup + live-pass dedup backstop

**Files:**
- Create: `MyApp/AI/PointDedup.swift`
- Modify: `MyApp/AI/FinalPolisher.swift` (use PointDedup; delete private helpers)
- Modify: `MyApp/AI/LiveExtractor.swift` (dedup backstop)
- Create: `RevueAITests/PointDedupTests.swift`
- Modify: `RevueAITests/LiveExtractorTests.swift`

**Interfaces:**
- Consumes: the normalize/similar logic currently private in `FinalPolisher`.
- Produces: `PointDedup.normalize(_ text: String) -> String`, `PointDedup.similar(_ a: String, _ b: String) -> Bool` (both take/compare normalized strings), `PointDedup.containsSimilar(_ candidate: String, in existing: [String]) -> Bool` (raw strings; empty candidates count as duplicates).

- [ ] **Step 1: Write the failing tests**

Create `RevueAITests/PointDedupTests.swift`:

```swift
import Foundation
import Testing
@testable import RevueAI

struct PointDedupTests {
    @Test func normalizeStripsPunctuationAndCase() {
        #expect(PointDedup.normalize("Add retry-logic, NOW!") == "add retry logic now")
    }

    @Test func identicalPhrasesAreSimilar() {
        #expect(PointDedup.containsSimilar("Add retry logic", in: ["add retry logic"]))
    }

    @Test func containmentIsSimilar() {
        #expect(PointDedup.containsSimilar(
            "Add retry logic",
            in: ["Add retry logic to the upload path"]
        ))
    }

    @Test func highWordOverlapIsSimilar() {
        #expect(PointDedup.containsSimilar(
            "Add retry logic to upload path",
            in: ["Add retry logic to the upload path"]
        ))
    }

    @Test func distinctPointsAreNotSimilar() {
        #expect(!PointDedup.containsSimilar(
            "Add pagination to the list endpoint",
            in: ["Add retry logic to the upload path"]
        ))
    }

    @Test func emptyCandidateCountsAsDuplicate() {
        #expect(PointDedup.containsSimilar("  ", in: []))
    }
}
```

Add to `RevueAITests/LiveExtractorTests.swift`:

```swift
    @Test func skipsNearDuplicateLivePoints() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let existing = ActionItem(oneLiner: "Add retry logic to the upload path", order: 0)
        existing.note = note
        context.insert(existing)
        let model = FakeReviewModel()
        model.extractResults = [.success(ExtractedPoints(
            actionItems: [
                ActionItemCandidate(oneLiner: "Add retry logic to upload path", attribution: "R", supportingQuote: ""),
                ActionItemCandidate(oneLiner: "Add pagination to the list endpoint", attribution: "R", supportingQuote: ""),
            ],
            decisions: [],
            openQuestions: []
        ))]
        let extractor = LiveExtractor(model: model)
        try await extractor.extractAndCheckpoint(chunk: "[reviewer] talk", into: note, context: context)
        #expect(note.sortedActionItems.map(\.oneLiner) == [
            "Add retry logic to the upload path",
            "Add pagination to the list endpoint",
        ])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: BUILD FAILURE — `PointDedup` doesn't exist.

- [ ] **Step 3: Implement PointDedup and wire it in**

Create `MyApp/AI/PointDedup.swift` (logic moved verbatim from `FinalPolisher`):

```swift
import Foundation

/// Fuzzy near-duplicate detection for extracted points — the code-level
/// backstop behind the prompts' merge / known-points instructions.
enum PointDedup {
    /// Normalizes a phrase to lowercase alphanumeric words for comparison.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// True when two normalized phrases are near-duplicates — one contains the
    /// other, or they share at least 80% of the smaller phrase's words.
    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b || a.contains(b) || b.contains(a) { return true }
        let wordsA = Set(a.split(separator: " "))
        let wordsB = Set(b.split(separator: " "))
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return false }
        let overlap = wordsA.intersection(wordsB).count
        return Double(overlap) / Double(min(wordsA.count, wordsB.count)) >= 0.8
    }

    /// True when `candidate` is a near-duplicate of anything in `existing`.
    /// Takes raw strings. An empty/whitespace candidate counts as a duplicate
    /// so callers uniformly skip it.
    static func containsSimilar(_ candidate: String, in existing: [String]) -> Bool {
        let key = normalize(candidate)
        guard !key.isEmpty else { return true }
        return existing.contains { similar(normalize($0), key) }
    }
}
```

In `MyApp/AI/FinalPolisher.swift`:
- Delete the private `normalize` and `similar` functions.
- In `apply`, rework the three dedup loops to use raw strings via `containsSimilar`. The action-items loop becomes:

```swift
        var seen: [String] = []
        var order = 0
        for item in result.actionItems {
            guard !PointDedup.containsSimilar(item.oneLiner, in: seen) else { continue }
            seen.append(item.oneLiner)
            let actionItem = ActionItem(
                oneLiner: item.oneLiner,
                rationale: item.rationale,
                inDepthDetail: item.inDepthDetail,
                attribution: item.attribution,
                supportingQuotes: item.supportingQuotes,
                priority: item.priority.priority,
                category: item.category.category,
                order: order
            )
            actionItem.note = note
            context.insert(actionItem)
            order += 1
        }
```

The open-questions loop becomes:

```swift
        var seenQuestions: [String] = []
        var questionOrder = 0
        for question in result.openQuestions {
            guard !PointDedup.containsSimilar(question.question, in: seenQuestions) else { continue }
            seenQuestions.append(question.question)
            let openQuestion = OpenQuestion(
                text: question.question,
                attribution: question.attribution,
                order: questionOrder
            )
            openQuestion.note = note
            context.insert(openQuestion)
            questionOrder += 1
        }
```

The decisions loop (added in Task 7) becomes:

```swift
        var seenDecisions: [String] = []
        var decisionOrder = 0
        for decision in result.decisions {
            guard !PointDedup.containsSimilar(decision.statement, in: seenDecisions) else { continue }
            seenDecisions.append(decision.statement)
            let record = Decision(
                statement: decision.statement,
                attribution: decision.attribution,
                order: decisionOrder
            )
            record.note = note
            context.insert(record)
            decisionOrder += 1
        }
```

In `MyApp/AI/LiveExtractor.swift` `extractAndCheckpoint`, add the backstop. Replace the action-items loop with:

```swift
        var knownOneLiners = (note.actionItems ?? []).map(\.oneLiner)
        var order = note.actionItems?.count ?? 0
        for candidate in points.actionItems {
            guard !PointDedup.containsSimilar(candidate.oneLiner, in: knownOneLiners) else { continue }
            knownOneLiners.append(candidate.oneLiner)
            let quotes = candidate.supportingQuote.isEmpty ? [] : [candidate.supportingQuote]
            let item = ActionItem(
                oneLiner: candidate.oneLiner,
                attribution: candidate.attribution,
                supportingQuotes: quotes,
                order: order
            )
            item.note = note
            context.insert(item)
            order += 1
        }
```

Replace the open-questions loop with:

```swift
        var knownQuestions = (note.openQuestions ?? []).map(\.text)
        var questionOrder = note.openQuestions?.count ?? 0
        for candidate in points.openQuestions {
            guard !PointDedup.containsSimilar(candidate.question, in: knownQuestions) else { continue }
            knownQuestions.append(candidate.question)
            let question = OpenQuestion(
                text: candidate.question,
                attribution: candidate.attribution,
                order: questionOrder
            )
            question.note = note
            context.insert(question)
            questionOrder += 1
        }
```

Replace the decisions loop (added in Task 7) with:

```swift
        var knownDecisions = (note.decisions ?? []).map(\.statement)
        var decisionOrder = note.decisions?.count ?? 0
        for candidate in points.decisions {
            guard !PointDedup.containsSimilar(candidate.statement, in: knownDecisions) else { continue }
            knownDecisions.append(candidate.statement)
            let decision = Decision(
                statement: candidate.statement,
                attribution: candidate.attribution,
                order: decisionOrder
            )
            decision.note = note
            context.insert(decision)
            decisionOrder += 1
        }
```

- [ ] **Step 4: Run the full suite**

Run: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet`
Expected: `** TEST SUCCEEDED **` — all tests from all tasks.

- [ ] **Step 5: Commit**

```bash
git add MyApp RevueAITests
git commit -m "refactor: shared PointDedup backstop for live and final passes"
```

---

## Final verification (after Task 10)

- [ ] Run the full suite one more time: `xcodebuild test -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet` → `** TEST SUCCEEDED **`
- [ ] Build the app: `xcodebuild build -project RevueAI.xcodeproj -scheme RevueAI -destination 'platform=macOS' -quiet` → `** BUILD SUCCEEDED **`
- [ ] Manual smoke test (needs the user): start a capture from the menu bar, speak a few sentences, stop, and confirm the note shows a summary, action items, and (if any were stated) decisions.
