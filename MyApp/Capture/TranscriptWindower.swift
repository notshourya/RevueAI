import Foundation

/// Splits a transcript into windows that each fit a token budget, with a small
/// segment overlap so points spanning a boundary aren't lost. Pure and
/// stateless. Token counts use a ~4 characters/token heuristic — deliberately
/// rough; budgets are chosen with headroom.
enum TranscriptWindower {
    /// Trailing segments repeated at the start of the next window.
    static let overlapSegments = 2
    static let charactersPerToken = 4

    /// "[hint] text\n" — brackets, space, newline ≈ 4 extra characters.
    private static func characters(_ segment: AudioSegment) -> Int {
        segment.text.count + segment.speakerHint.rawValue.count + 4
    }

    static func estimatedTokens(_ segments: [AudioSegment]) -> Int {
        segments.reduce(0) { $0 + characters($1) } / charactersPerToken
    }

    /// A single segment larger than the budget still gets a window of its own
    /// (never dropped) — the backend may truncate, but content is not lost here.
    ///
    /// The accumulator tracks characters (not per-segment floored tokens) so
    /// the budget check is exactly `estimatedTokens(window) <= tokenBudget` —
    /// summing floored per-segment costs would under-count and let windows
    /// exceed the budget by rounding drift.
    static func windows(for segments: [AudioSegment], tokenBudget: Int) -> [[AudioSegment]] {
        guard !segments.isEmpty else { return [] }
        guard estimatedTokens(segments) > tokenBudget else { return [segments] }

        var result: [[AudioSegment]] = []
        var current: [AudioSegment] = []
        var currentCharacters = 0
        for segment in segments {
            let cost = characters(segment)
            if !current.isEmpty, (currentCharacters + cost) / charactersPerToken > tokenBudget {
                result.append(current)
                let overlap = Array(current.suffix(overlapSegments))
                current = overlap
                currentCharacters = overlap.reduce(0) { $0 + characters($1) }
            }
            current.append(segment)
            currentCharacters += cost
        }
        if current.count > overlapSegments || result.isEmpty {
            result.append(current)
        }
        return result
    }
}
