import Foundation
import FoundationModels

/// The single seam over all AI backends. The pipeline talks only to this
/// protocol, so on-device, Private Cloud Compute, and BYO-key backends are
/// interchangeable ("dynamic profiling") without any pipeline changes.
protocol ReviewLanguageModel: Sendable {
    /// Whether this backend is currently usable.
    var isAvailable: Bool { get }

    /// Approximate prompt-token budget for a single request to this backend,
    /// with headroom for instructions and output. Drives transcript windowing.
    var contextTokenBudget: Int { get }

    /// Live pass: extract new typed points from a fresh transcript chunk,
    /// given a compact list of already-known points to avoid duplicates.
    func extractPoints(fromChunk chunk: String, knownPoints: String) async throws -> ExtractedPoints

    /// Final pass: consolidate the whole transcript + live points into a
    /// polished review (summary, verdict, in-depth action items, questions).
    func polish(transcript: String, livePoints: String) async throws -> PolishedReview
}

// MARK: - Shared prompt text

enum ReviewPrompts {
    static let liveInstructions = """
    You extract structured notes from a technical review or standup transcript. \
    Return only NEW action items, decisions, and open questions found in the \
    provided chunk that are not already in the known points. Be concise and \
    faithful to what was said. Do not invent content.
    """

    static let polishInstructions = """
    You polish the notes from a completed technical review into a clean, \
    de-duplicated result. Rules:
    • MERGE aggressively. If two points describe the same underlying issue, \
    combine them into ONE action item — never list the same idea twice, even \
    if it was mentioned by different people or in different words.
    • For each action item provide layered depth: a short imperative title, a \
    ONE-sentence rationale (why it matters / impact if ignored), and a deeper \
    detail paragraph with a concrete suggested approach.
    • Assign each item a priority (blocker, major, minor, nit) and a category \
    (bug, refactor, performance, security, testing, design, documentation, \
    question, other).
    • Fix speaker attribution using the full conversation. Add short verbatim \
    supporting quotes only when they exist in the transcript.
    • Write a 2–4 sentence summary and an overall verdict.
    Be faithful to the transcript; never fabricate details or quotes.
    """
}

// MARK: - On-device backend (default for Milestone 1)

/// Runs both passes on the on-device `SystemLanguageModel`.
nonisolated struct OnDeviceReviewModel: ReviewLanguageModel {
    var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: return true
        default: return false
        }
    }

    var contextTokenBudget: Int { 3000 }

    func extractPoints(fromChunk chunk: String, knownPoints: String) async throws -> ExtractedPoints {
        let session = LanguageModelSession(instructions: ReviewPrompts.liveInstructions)
        let prompt = """
        KNOWN POINTS SO FAR:
        \(knownPoints.isEmpty ? "(none)" : knownPoints)

        NEW TRANSCRIPT CHUNK:
        \(chunk)
        """
        let response = try await session.respond(to: prompt, generating: ExtractedPoints.self)
        return response.content
    }

    func polish(transcript: String, livePoints: String) async throws -> PolishedReview {
        let session = LanguageModelSession(instructions: ReviewPrompts.polishInstructions)
        let prompt = """
        LIVE-EXTRACTED POINTS:
        \(livePoints.isEmpty ? "(none)" : livePoints)

        FULL TRANSCRIPT:
        \(transcript)
        """
        let response = try await session.respond(to: prompt, generating: PolishedReview.self)
        return response.content
    }
}

// MARK: - Private Cloud Compute backend (entitlement-gated; off by default)

/// Routes the final (and optionally live) pass through Private Cloud Compute.
/// Present behind the protocol now; enabled once the PCC entitlement is granted.
nonisolated struct PrivateCloudReviewModel: ReviewLanguageModel {
    var isAvailable: Bool {
        switch PrivateCloudComputeLanguageModel().availability {
        case .available: return true
        default: return false
        }
    }

    var contextTokenBudget: Int { 24000 }

    func extractPoints(fromChunk chunk: String, knownPoints: String) async throws -> ExtractedPoints {
        let session = LanguageModelSession(
            model: PrivateCloudComputeLanguageModel(),
            instructions: ReviewPrompts.liveInstructions
        )
        let prompt = """
        KNOWN POINTS SO FAR:
        \(knownPoints.isEmpty ? "(none)" : knownPoints)

        NEW TRANSCRIPT CHUNK:
        \(chunk)
        """
        return try await session.respond(to: prompt, generating: ExtractedPoints.self).content
    }

    func polish(transcript: String, livePoints: String) async throws -> PolishedReview {
        let session = LanguageModelSession(
            model: PrivateCloudComputeLanguageModel(),
            instructions: ReviewPrompts.polishInstructions
        )
        let prompt = """
        LIVE-EXTRACTED POINTS:
        \(livePoints.isEmpty ? "(none)" : livePoints)

        FULL TRANSCRIPT:
        \(transcript)
        """
        return try await session.respond(to: prompt, generating: PolishedReview.self).content
    }
}

// MARK: - Backend selection

enum ReviewModelBackend: String, CaseIterable, Sendable {
    /// On-device `SystemLanguageModel` — the Milestone 1 default.
    case onDevice
    /// Private Cloud Compute — enabled once entitled.
    case privateCloudCompute
    /// Bring-your-own API key (e.g. Claude) — a future custom `LanguageModelExecutor`.
    case customAPIKey
}

enum ReviewModelFactory {
    /// The backend the pipeline uses for now. Final pass falls back to
    /// on-device automatically because that is the default here.
    static func make(_ backend: ReviewModelBackend = .onDevice) -> any ReviewLanguageModel {
        switch backend {
        case .onDevice: return OnDeviceReviewModel()
        case .privateCloudCompute: return PrivateCloudReviewModel()
        case .customAPIKey: return OnDeviceReviewModel() // TODO: custom LanguageModelExecutor
        }
    }
}
