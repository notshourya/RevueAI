import Foundation

/// Produces finalized transcript phrases from a live audio source.
///
/// Abstracting transcription behind a protocol lets the pipeline run with a
/// scripted `MockTranscriptionService` (previews, unit tests, and before the
/// microphone entitlement is configured) and swap in the real
/// `SpeechTranscriptionService` without any coordinator changes.
protocol TranscriptionProviding: AnyObject, Sendable {
    /// Ensures assets/permissions, starts capture, and returns a stream that
    /// yields each *finalized* phrase (volatile partials are filtered out).
    func start() async throws -> AsyncThrowingStream<String, Error>

    /// Stops capture and finishes analysis.
    func stop() async
}

/// A scripted transcription source for previews, tests, and entitlement-free
/// runs. Emits the provided phrases on a timer to imitate a live meeting.
final class MockTranscriptionService: TranscriptionProviding {
    private let phrases: [String]
    private let interval: Duration
    private var task: Task<Void, Never>?

    init(phrases: [String], interval: Duration = .seconds(2)) {
        self.phrases = phrases
        self.interval = interval
    }

    func start() async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [phrases, interval] in
                for phrase in phrases {
                    if Task.isCancelled { break }
                    try? await Task.sleep(for: interval)
                    continuation.yield(phrase)
                }
                continuation.finish()
            }
            self.task = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() async {
        task?.cancel()
        task = nil
    }
}
