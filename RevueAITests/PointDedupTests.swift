import Foundation
import Testing
@testable import RevueAI

struct PointDedupTests {
    @Test func normalizeStripsPunctuationAndCase() {
        #expect(PointDedup.normalize("Add retry-logic, NOW!") == "add retry logic now")
    }

    @Test func identicalPhrasesAreSimilar() {
        #expect(PointDedup.containsSimilar("Add retry logic", in: ["add retry logic"]))
    }

    @Test func containmentIsSimilar() {
        #expect(PointDedup.containsSimilar(
            "Add retry logic",
            in: ["Add retry logic to the upload path"]
        ))
    }

    @Test func highWordOverlapIsSimilar() {
        #expect(PointDedup.containsSimilar(
            "Add retry logic to upload path",
            in: ["Add retry logic to the upload path"]
        ))
    }

    @Test func distinctPointsAreNotSimilar() {
        #expect(!PointDedup.containsSimilar(
            "Add pagination to the list endpoint",
            in: ["Add retry logic to the upload path"]
        ))
    }

    @Test func emptyCandidateCountsAsDuplicate() {
        #expect(PointDedup.containsSimilar("  ", in: []))
    }
}
