import Testing
@testable import RevueAI

struct SmokeTests {
    @Test func rollingTranscriptStartsEmpty() {
        let transcript = RollingTranscript()
        #expect(transcript.isEmpty)
    }
}
