import Foundation
import Testing
@testable import RevueAI

@MainActor
struct SourceLogTests {
    @Test func dedupsAndPreservesFirstRecordedOrder() throws {
        let context = try makeInMemoryContext()
        let first = ReviewNote(title: "First")
        let second = ReviewNote(title: "Second")
        context.insert(first)
        context.insert(second)
        let log = SourceLog()
        log.record(first)
        log.record(second)
        log.record(first)
        let refs = log.snapshot()
        #expect(refs.map(\.title) == ["First", "Second"])
    }

    @Test func capsAtEight() throws {
        let context = try makeInMemoryContext()
        let log = SourceLog()
        for index in 0..<12 {
            let note = ReviewNote(title: "Note \(index)")
            context.insert(note)
            log.record(note)
        }
        #expect(log.snapshot().count == 8)
        #expect(log.snapshot().first?.title == "Note 0")
    }

    @Test func resetEmptiesTheLog() throws {
        let context = try makeInMemoryContext()
        let note = ReviewNote(title: "N")
        context.insert(note)
        let log = SourceLog()
        log.record(note)
        log.reset()
        #expect(log.snapshot().isEmpty)
    }
}
