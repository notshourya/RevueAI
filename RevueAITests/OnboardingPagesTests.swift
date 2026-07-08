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

    @Test func pageIDsAndArtAreUnique() {
        #expect(Set(OnboardingPage.all.map(\.id)).count == OnboardingPage.all.count)
        #expect(Set(OnboardingPage.all.map(\.art)).count == OnboardingPage.all.count)
    }

    @Test func slidesCoverPrivacyBoardRulerAssistant() {
        let text = OnboardingPage.all.map { $0.title + " " + $0.subtitle }
            .joined(separator: " ")
            .lowercased()
        #expect(text.contains("recorded"))
        #expect(text.contains("board"))
        #expect(text.contains("ruler"))
        #expect(text.contains("cites"))
    }
}
