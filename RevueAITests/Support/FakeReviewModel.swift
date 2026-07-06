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
    var contextTokenBudget = 3000
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
