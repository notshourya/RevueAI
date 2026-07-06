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
