import Foundation
import Testing
@testable import RevueAI

struct TourModelTests {
    @Test func actsAreWellFormed() {
        #expect(!TourScript.act1.isEmpty)
        #expect(!TourScript.act2.isEmpty)
        let ids = (TourScript.act1 + TourScript.act2).map(\.id)
        #expect(Set(ids).count == ids.count)
        for stop in TourScript.act1 + TourScript.act2 {
            #expect(!stop.title.isEmpty)
            #expect(!stop.body.isEmpty)
        }
    }

    @Test func act1EndsWithCenteredCaptureCard() {
        let last = TourScript.act1.last!
        #expect(last.anchorID == nil)
        #expect(last.actionTitle != nil)
    }

    @Test @MainActor func controllerWalksAndFinishes() {
        let controller = TourController()
        var finished = false
        let stops = [TourStop(id: "a", title: "A", body: "a"),
                     TourStop(id: "b", title: "B", body: "b")]
        controller.begin(stops) { finished = true }
        #expect(controller.current?.id == "a")
        controller.advance()
        #expect(controller.current?.id == "b")
        #expect(controller.isLastStop)
        controller.advance()
        #expect(finished)
        #expect(!controller.isActive)
        #expect(controller.current == nil)
    }

    @Test @MainActor func skipFinishesImmediately() {
        let controller = TourController()
        var finished = false
        controller.begin([TourStop(id: "a", title: "A", body: "a")]) { finished = true }
        controller.skip()
        #expect(finished)
        #expect(!controller.isActive)
    }

    @Test @MainActor func beginWithNoStopsIsIgnored() {
        let controller = TourController()
        var finished = false
        controller.begin([]) { finished = true }
        #expect(!controller.isActive)
        #expect(!finished)
    }

    @Test func boardTourTriggerPredicate() {
        #expect(TourScript.shouldRunBoardTour(itemCount: 3, hasSeenBoardTour: false))
        #expect(!TourScript.shouldRunBoardTour(itemCount: 0, hasSeenBoardTour: false))
        #expect(!TourScript.shouldRunBoardTour(itemCount: 3, hasSeenBoardTour: true))
    }
}
