import Foundation
import Testing
@testable import RevueAI

struct RollingTranscriptTests {
    private func seg(_ text: String, hint: SpeakerHint = .presenter) -> AudioSegment {
        AudioSegment(speakerHint: hint, text: text)
    }

    @Test func drainReturnsOnlyFreshSegmentsOnce() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        transcript.append(seg("two"))
        #expect(transcript.drainNewSegments().map(\.text) == ["one", "two"])
        #expect(transcript.drainNewSegments().isEmpty)
        transcript.append(seg("three"))
        #expect(transcript.drainNewSegments().map(\.text) == ["three"])
    }

    @Test func fullTextFormatsAttributedLines() {
        let transcript = RollingTranscript()
        transcript.append(seg("hello", hint: .presenter))
        transcript.append(seg("hi there", hint: .reviewer))
        #expect(transcript.fullText() == "[presenter] hello\n[reviewer] hi there")
    }

    @Test func clearResetsEverything() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        _ = transcript.drainNewSegments()
        transcript.clear()
        #expect(transcript.isEmpty)
        #expect(transcript.drainNewSegments().isEmpty)
    }
}
