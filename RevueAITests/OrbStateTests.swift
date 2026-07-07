import Foundation
import Testing
@testable import RevueAI

struct OrbStateTests {
    @Test func idleMapsToIdle() {
        #expect(OrbState.from(captureState: .idle, isExtracting: false, hasError: false) == .idle)
    }

    @Test func listeningMapsToListening() {
        #expect(OrbState.from(captureState: .listening, isExtracting: false, hasError: false) == .listening)
    }

    @Test func listeningWhileExtractingShimmers() {
        #expect(OrbState.from(captureState: .listening, isExtracting: true, hasError: false) == .extracting)
    }

    @Test func pausedMapsToPaused() {
        #expect(OrbState.from(captureState: .paused, isExtracting: false, hasError: false) == .paused)
    }

    @Test func processingMapsToProcessing() {
        #expect(OrbState.from(captureState: .processing, isExtracting: false, hasError: false) == .processing)
    }

    @Test func idleWithErrorShowsError() {
        #expect(OrbState.from(captureState: .idle, isExtracting: false, hasError: true) == .error)
    }

    @Test func activeCaptureOutranksError() {
        #expect(OrbState.from(captureState: .listening, isExtracting: false, hasError: true) == .listening)
    }
}
