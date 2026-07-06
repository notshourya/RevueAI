import Foundation
import Testing
@testable import RevueAI

struct RollingTranscriptTests {
    private func seg(_ text: String, hint: SpeakerHint = .presenter) -> AudioSegment {
        AudioSegment(speakerHint: hint, text: text)
    }

    @Test func peekDoesNotAdvanceTheWatermark() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        #expect(transcript.peekNewSegments().map(\.text) == ["one"])
        #expect(transcript.peekNewSegments().map(\.text) == ["one"])
    }

    @Test func commitAdvancesByCount() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        transcript.append(seg("two"))
        let fresh = transcript.peekNewSegments()
        transcript.commitExtracted(count: fresh.count)
        #expect(transcript.peekNewSegments().isEmpty)
        transcript.append(seg("three"))
        #expect(transcript.peekNewSegments().map(\.text) == ["three"])
    }

    @Test func failedExtractionKeepsSegmentsQueued() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        _ = transcript.peekNewSegments()   // extraction ran but failed: no commit
        transcript.append(seg("two"))
        #expect(transcript.peekNewSegments().map(\.text) == ["one", "two"])
    }

    @Test func segmentsArrivingDuringExtractionStayQueued() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        let fresh = transcript.peekNewSegments()
        transcript.append(seg("two"))          // arrives while the model call is in flight
        transcript.commitExtracted(count: fresh.count)
        #expect(transcript.peekNewSegments().map(\.text) == ["two"])
    }

    @Test func commitNeverOverruns() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        transcript.commitExtracted(count: 99)
        #expect(transcript.peekNewSegments().isEmpty)
        transcript.append(seg("two"))
        #expect(transcript.peekNewSegments().map(\.text) == ["two"])
    }

    @Test func fullTextFormatsAttributedLines() {
        let transcript = RollingTranscript()
        transcript.append(seg("hello", hint: .presenter))
        transcript.append(seg("hi there", hint: .reviewer))
        #expect(transcript.fullText() == "[presenter] hello\n[reviewer] hi there")
    }

    @Test func pendingCountTracksUncommittedSegments() {
        let transcript = RollingTranscript()
        #expect(transcript.pendingCount == 0)
        transcript.append(seg("one"))
        transcript.append(seg("two"))
        #expect(transcript.pendingCount == 2)
        transcript.commitExtracted(count: 1)
        #expect(transcript.pendingCount == 1)
    }

    @Test func clearResetsEverything() {
        let transcript = RollingTranscript()
        transcript.append(seg("one"))
        _ = transcript.peekNewSegments()
        transcript.clear()
        #expect(transcript.isEmpty)
        #expect(transcript.peekNewSegments().isEmpty)
    }
}
