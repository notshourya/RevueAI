import Foundation
import Testing
@testable import RevueAI

struct ActionItemCurationTests {
    @Test func allTagsReturnsDistinctSortedTags() throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "T")
        context.insert(note)
        let a = ActionItem(oneLiner: "A", tags: ["backend", "urgent"], order: 0)
        a.note = note
        context.insert(a)
        let b = ActionItem(oneLiner: "B", tags: ["urgent", "api"], order: 1)
        b.note = note
        context.insert(b)
        try context.save()
        #expect(ActionItem.allTags(in: context) == ["api", "backend", "urgent"])
    }

    @Test func allTagsIsEmptyWhenNoTags() throws {
        let context = try makeInMemoryContext()
        #expect(ActionItem.allTags(in: context) == [])
    }
}
