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
