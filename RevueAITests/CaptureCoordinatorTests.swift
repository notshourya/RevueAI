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
}
