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

    /// Segments captured since the last committed extraction. Does NOT advance
    /// the watermark — call `commitExtracted(count:)` after the model call
    /// succeeds, so a failed extraction leaves the chunk queued for retry.
    func peekNewSegments() -> [AudioSegment] {
        guard lastExtractedIndex < segments.count else { return [] }
        return Array(segments[lastExtractedIndex...])
    }

    /// Marks `count` peeked segments as extracted. Counting (rather than
    /// draining) means segments that arrived while the model call was in
    /// flight stay queued.
    func commitExtracted(count: Int) {
        lastExtractedIndex = min(lastExtractedIndex + count, segments.count)
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
