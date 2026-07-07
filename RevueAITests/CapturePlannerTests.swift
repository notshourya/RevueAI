import Foundation
import Testing
@testable import RevueAI

@MainActor
struct CapturePlannerTests {
    @Test func armCreatesAPlannedCapture() throws {
        let context = try makeInMemoryContext()
        let event = MeetingEvent.stub()
        CapturePlanner.arm(event, in: context)
        #expect(CapturePlanner.isArmed(event, in: context))
    }

    @Test func disarmRemovesIt() throws {
        let context = try makeInMemoryContext()
        let event = MeetingEvent.stub()
        CapturePlanner.arm(event, in: context)
        CapturePlanner.disarm(event, in: context)
        #expect(!CapturePlanner.isArmed(event, in: context))
    }

    @Test func armingIsIdempotent() throws {
        let context = try makeInMemoryContext()
        let event = MeetingEvent.stub()
        CapturePlanner.arm(event, in: context)
        CapturePlanner.arm(event, in: context)
        CapturePlanner.disarm(event, in: context)
        #expect(!CapturePlanner.isArmed(event, in: context))
    }

    @Test func consumeReturnsAndDeletesTheMatch() throws {
        let context = try makeInMemoryContext()
        let event = MeetingEvent.stub()
        CapturePlanner.arm(event, in: context)
        let consumed = CapturePlanner.consume(eventID: event.id, occurrenceDate: event.start, in: context)
        #expect(consumed != nil)
        #expect(!CapturePlanner.isArmed(event, in: context))
    }

    @Test func pruneDropsStaleCaptures() throws {
        let context = try makeInMemoryContext()
        let old = MeetingEvent.stub(id: "old", start: .now.addingTimeInterval(-7200))
        let upcoming = MeetingEvent.stub(id: "new", start: .now.addingTimeInterval(3600))
        CapturePlanner.arm(old, in: context)
        CapturePlanner.arm(upcoming, in: context)
        CapturePlanner.prune(now: .now, in: context)
        #expect(!CapturePlanner.isArmed(old, in: context))
        #expect(CapturePlanner.isArmed(upcoming, in: context))
    }

    @Test func duePromptReturnsMeetingThatJustStarted() throws {
        let context = try makeInMemoryContext()
        let due = MeetingEvent.stub(id: "due", start: .now.addingTimeInterval(-60))
        let later = MeetingEvent.stub(id: "later", start: .now.addingTimeInterval(3600))
        CapturePlanner.arm(due, in: context)
        CapturePlanner.arm(later, in: context)
        let prompt = CapturePlanner.duePrompt(now: .now, in: context)
        #expect(prompt?.eventID == "due")
    }
}
