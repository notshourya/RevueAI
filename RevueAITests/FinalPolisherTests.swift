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

    @Test func userEditedItemsSurvivePolish() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let edited = ActionItem(oneLiner: "Ship the fix to production", userModified: true, order: 0)
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
        await polisher.polish(note: note, segments: [seg("hi")], context: context)
        #expect(note.sortedActionItems.map(\.oneLiner) == [
            "Ship the fix to production",
            "Completely new item",
        ])
    }

    @Test func aiNearDuplicateOfEditedItemIsDropped() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let edited = ActionItem(oneLiner: "Add retry logic to the upload path", userModified: true, order: 0)
        edited.note = note
        context.insert(edited)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(actionItems: [
            .stub("Add retry logic to upload path"),
            .stub("Add pagination to the list endpoint"),
        ]))]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [seg("hi")], context: context)
        #expect(note.sortedActionItems.map(\.oneLiner) == [
            "Add retry logic to the upload path",
            "Add pagination to the list endpoint",
        ])
    }

    @Test func userCreatedItemsSurvivePolish() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let manual = ActionItem(oneLiner: "Manually added task", isUserCreated: true, order: 0)
        manual.note = note
        context.insert(manual)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(actionItems: []))]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [seg("hi")], context: context)
        #expect(note.sortedActionItems.map(\.oneLiner) == ["Manually added task"])
    }

    @Test func preservedItemsKeepOrderBeforePolishedOnes() async throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let first = ActionItem(oneLiner: "Edited A", userModified: true, order: 3)
        first.note = note
        context.insert(first)
        let second = ActionItem(oneLiner: "Edited B", userModified: true, order: 7)
        second.note = note
        context.insert(second)
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub(actionItems: [.stub("New from AI")]))]
        let polisher = FinalPolisher(model: model)
        await polisher.polish(note: note, segments: [seg("hi")], context: context)
        #expect(note.sortedActionItems.map(\.oneLiner) == ["Edited A", "Edited B", "New from AI"])
        #expect(note.sortedActionItems.map(\.order) == [0, 1, 2])
    }
}
