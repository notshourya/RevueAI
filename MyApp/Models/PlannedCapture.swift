import Foundation
import SwiftData

/// One armed meeting occurrence: "prompt me to capture when this starts."
/// Created by the calendar's arm toggle; consumed when the capture starts
/// or pruned once the occurrence is long past.
@Model
final class PlannedCapture {
    var id: UUID = UUID()
    var eventID: String = ""
    var seriesID: String = ""
    var occurrenceDate: Date = Date()
    var title: String = ""

    init(eventID: String = "", seriesID: String = "", occurrenceDate: Date = .now, title: String = "") {
        self.eventID = eventID
        self.seriesID = seriesID
        self.occurrenceDate = occurrenceDate
        self.title = title
    }
}
