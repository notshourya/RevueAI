import Foundation
import Testing
@testable import RevueAI

struct TranscriptWindowerTests {
    private func seg(_ text: String) -> AudioSegment {
        AudioSegment(speakerHint: .reviewer, text: text)
    }

    /// 60 segments of ~40 characters each ≈ 600+ estimated tokens.
    /// Stored (not computed) so repeated accesses compare equal — AudioSegment's
    /// Equatable includes its UUID, so a computed property would mint fresh
    /// non-equal segments on every access.
    private let longTranscript: [AudioSegment] = (0..<60).map {
        AudioSegment(speakerHint: .reviewer, text: "Segment number \($0) with some padding text")
    }

    @Test func emptyInputYieldsNoWindows() {
        #expect(TranscriptWindower.windows(for: [], tokenBudget: 100).isEmpty)
    }

    @Test func transcriptUnderBudgetIsOneWindow() {
        let segments = [seg("short"), seg("also short")]
        let windows = TranscriptWindower.windows(for: segments, tokenBudget: 1000)
        #expect(windows.count == 1)
        #expect(windows[0] == segments)
    }

    @Test func windowsRespectTheBudget() {
        let windows = TranscriptWindower.windows(for: longTranscript, tokenBudget: 100)
        #expect(windows.count > 1)
        for window in windows {
            #expect(TranscriptWindower.estimatedTokens(window) <= 100)
        }
    }

    @Test func consecutiveWindowsOverlap() {
        let windows = TranscriptWindower.windows(for: longTranscript, tokenBudget: 100)
        for i in 1..<windows.count {
            let tail = Array(windows[i - 1].suffix(TranscriptWindower.overlapSegments))
            let head = Array(windows[i].prefix(TranscriptWindower.overlapSegments))
            #expect(tail == head)
        }
    }

    @Test func noSegmentIsLostOrReordered() {
        let windows = TranscriptWindower.windows(for: longTranscript, tokenBudget: 100)
        var reconstructed = windows[0]
        for window in windows.dropFirst() {
            reconstructed += window.dropFirst(TranscriptWindower.overlapSegments)
        }
        #expect(reconstructed == longTranscript)
    }

    @Test func oversizedSingleSegmentGetsItsOwnWindow() {
        let huge = seg(String(repeating: "x", count: 2000))
        let windows = TranscriptWindower.windows(for: [seg("small"), huge, seg("small too")], tokenBudget: 50)
        #expect(windows.flatMap { $0 }.contains(huge))
    }
}
