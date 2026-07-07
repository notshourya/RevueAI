import Foundation
import Testing
@testable import RevueAI

struct FloatingOrbControllerTests {
    @Test func floatsWhileCaptureIsActive() {
        #expect(FloatingOrbController.shouldFloat(state: .listening, enabled: true))
        #expect(FloatingOrbController.shouldFloat(state: .paused, enabled: true))
        #expect(FloatingOrbController.shouldFloat(state: .processing, enabled: true))
    }

    @Test func neverFloatsWhenIdle() {
        #expect(!FloatingOrbController.shouldFloat(state: .idle, enabled: true))
    }

    @Test func neverFloatsWhenDisabled() {
        #expect(!FloatingOrbController.shouldFloat(state: .listening, enabled: false))
    }
}
