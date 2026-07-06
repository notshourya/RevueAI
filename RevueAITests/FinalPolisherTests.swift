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
