import Foundation

/// Which capture stream a finalized phrase originated from.
///
/// Milestone 1 is mic-only, but the origin is modeled now so the system-audio
/// stream slots in behind the same attribution seam later.
enum StreamOrigin: Sendable {
    case microphone
    case systemAudio
}

/// A coarse, session-scoped speaker classification derived from stream origin
/// (and later refined by the LLM / voice diarization).
enum SpeakerHint: String, Codable, Sendable {
    /// The local user / presenter (mic stream).
    case presenter
    /// A remote participant / reviewer (system-audio stream).
    case reviewer
}

/// The currency of the extraction pipeline: one finalized transcript phrase,
/// tagged with a speaker hint and a timestamp.
///
/// Lives only in memory — `AudioSegment` is intentionally *not* a SwiftData
/// model and is never written to disk, preserving the "no transcript
/// persistence" invariant.
struct AudioSegment: Identifiable, Sendable, Equatable {
    let id: UUID
    var speakerHint: SpeakerHint
    var text: String
    var timestamp: Date

    init(
        id: UUID = UUID(),
        speakerHint: SpeakerHint,
        text: String,
        timestamp: Date = .now
    ) {
        self.id = id
        self.speakerHint = speakerHint
        self.text = text
        self.timestamp = timestamp
    }
}
