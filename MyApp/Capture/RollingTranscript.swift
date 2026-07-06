import Foundation

/// The in-memory rolling transcript for a single capture session.
///
/// Privacy invariant: this type has no persistence path and performs no file
/// I/O. It holds finalized segments only while a session is live and is
/// discarded after the final extraction pass. Only the structured `ReviewNote`
/// survives.
@MainActor
final class RollingTranscript {
    private(set) var segments: [AudioSegment] = []

    /// Index marking where the last live-extraction pass consumed up to.
    private(set) var lastExtractedIndex: Int = 0

    var count: Int { segments.count }
    var isEmpty: Bool { segments.isEmpty }

    func append(_ segment: AudioSegment) {
        segments.append(segment)
    }

    /// Segments captured since the last live-extraction pass, and advances the
    /// watermark so each segment is sent to the live model exactly once.
    func drainNewSegments() -> [AudioSegment] {
        guard lastExtractedIndex < segments.count else { return [] }
        let fresh = Array(segments[lastExtractedIndex..<segments.count])
        lastExtractedIndex = segments.count
        return fresh
    }

    /// The full transcript as attributed lines, for the final polish pass.
    func fullText() -> String {
        segments
            .map { "[\($0.speakerHint.rawValue)] \($0.text)" }
            .joined(separator: "\n")
    }

    /// Wipe all in-memory state. Called after the final pass completes (or on
    /// discard) so no transcript lingers.
    func clear() {
        segments.removeAll()
        lastExtractedIndex = 0
    }
}
