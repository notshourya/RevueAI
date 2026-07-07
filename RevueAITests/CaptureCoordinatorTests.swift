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

    @Test func startWithMeetingStampsSnapshotAndTitle() async throws {
        let context = try makeInMemoryContext()
        let mic = MockTranscriptionService(phrases: ["hello"], interval: .milliseconds(5))
        let model = FakeReviewModel()
        model.polishResults = [.success(.stub())]
        let coordinator = CaptureCoordinator(
            transcription: mic,
            systemTranscription: FailingTranscriptionService(),
            model: model
        )
        coordinator.captureSystemAudio = false
        let meeting = MeetingEvent.stub(title: "Sprint review")
        CapturePlanner.arm(meeting, in: context)
        await coordinator.start(context: context, meeting: meeting)
        let note = try #require(try context.fetch(FetchDescriptor<ReviewNote>()).first)
        #expect(note.title == "Sprint review")
        #expect(note.meetingSnapshot?.attendees == ["Priya", "Marcus"])
        #expect(note.meetingSnapshot?.seriesID == "series-1")
        #expect(!CapturePlanner.isArmed(meeting, in: context))
        await coordinator.stop()
    }
}
