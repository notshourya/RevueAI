import Foundation
import SwiftUI

/// One step of a guided tour. `anchorID` names a target registered via
/// `.tourAnchor(_:)` — or one of the AppKit toolbar ids TourOverlay
/// resolves itself ("assistant-search", "export-menu"). nil renders the
/// stop as a centered card.
struct TourStop: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    var anchorID: String? = nil
    var arrowEdge: Edge = .bottom
    /// Optional prominent action on the stop (e.g. "Start a capture").
    var actionTitle: String? = nil
}

/// Drives one act of the tour: a linear walk over its stops.
/// Skipping counts as seen — it fires the same completion as finishing.
@Observable @MainActor
final class TourController {
    private(set) var stops: [TourStop] = []
    private(set) var index = 0
    private(set) var isActive = false
    private var onFinished: (() -> Void)?

    var current: TourStop? {
        guard isActive, stops.indices.contains(index) else { return nil }
        return stops[index]
    }

    var isLastStop: Bool { index >= stops.count - 1 }

    func begin(_ stops: [TourStop], onFinished: @escaping () -> Void) {
        guard !stops.isEmpty else { return }
        self.stops = stops
        self.onFinished = onFinished
        index = 0
        isActive = true
    }

    func advance() {
        guard isActive else { return }
        if isLastStop { finish() } else { index += 1 }
    }

    func skip() { finish() }

    private func finish() {
        guard isActive else { return }
        isActive = false
        stops = []
        index = 0
        onFinished?()
        onFinished = nil
    }
}

/// The two acts of the guided tour.
enum TourScript {
    static let act1: [TourStop] = [
        TourStop(id: "search",
                 title: "Ask across every review",
                 body: "Type a question here — the assistant answers from your notes and cites the reviews it used.",
                 anchorID: "assistant-search"),
        TourStop(id: "ruler",
                 title: "Your meetings, on a ruler",
                 body: "Scrub through your history like a timer dial. Settle on a past day to filter the library; click the date to see that day's agenda and arm meetings.",
                 anchorID: "date-ruler",
                 arrowEdge: .top),
        TourStop(id: "capture",
                 title: "Capture lives in your menu bar",
                 body: "Hit the orb in the menu bar when a review starts. Stop when it ends — the structured note is ready seconds later.",
                 actionTitle: "Start a capture"),
    ]

    static let act2: [TourStop] = [
        TourStop(id: "board",
                 title: "Work the board",
                 body: "Action items live in columns. Drag rows between To Do and Completed, or select several and complete them together.",
                 anchorID: "board-todo",
                 arrowEdge: .trailing),
        TourStop(id: "item",
                 title: "Every item opens up",
                 body: "Click a row for the full story — priority, tags, quotes. Your edits survive the AI's final polish.",
                 anchorID: "action-item",
                 arrowEdge: .bottom),
        TourStop(id: "export",
                 title: "Take the note with you",
                 body: "Copy the finished note as Markdown or share it from here.",
                 anchorID: "export-menu",
                 arrowEdge: .bottom),
    ]

    /// Act 2 fires only for a real note with extracted action items.
    static func shouldRunBoardTour(itemCount: Int, hasSeenBoardTour: Bool) -> Bool {
        itemCount > 0 && !hasSeenBoardTour
    }
}
