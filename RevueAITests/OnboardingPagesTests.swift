import Foundation
import Testing
@testable import RevueAI

struct OnboardingPagesTests {
    @Test func fiveCompletePages() {
        #expect(OnboardingPage.all.count == 5)
        for page in OnboardingPage.all {
            #expect(!page.title.isEmpty)
            #expect(!page.subtitle.isEmpty)
        }
    }

    @Test func tourCoversPermissionsAndCapture() {
        let titles = OnboardingPage.all.map(\.title).joined(separator: " ")
        #expect(titles.contains("Microphone"))
        #expect(titles.contains("Participants"))
    }
}
