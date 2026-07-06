import Foundation

/// Maps a finalized phrase and its stream origin onto an `AudioSegment` with a
/// speaker hint.
///
/// This is the seam the spec calls for: the MVP uses stream-of-origin
/// attribution; later, LLM context refinement and FluidAudio voice diarization
/// slot in behind the same protocol without touching the rest of the pipeline.
protocol SpeakerAttribution: Sendable {
    func attribute(text: String, origin: StreamOrigin, at time: Date) -> AudioSegment
}

/// MVP attribution: mic stream ⇒ presenter, system-audio stream ⇒ reviewer.
struct StreamOfOriginAttribution: SpeakerAttribution {
    func attribute(text: String, origin: StreamOrigin, at time: Date) -> AudioSegment {
        let hint: SpeakerHint = (origin == .microphone) ? .presenter : .reviewer
        return AudioSegment(speakerHint: hint, text: text, timestamp: time)
    }
}
