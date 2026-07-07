import Foundation
import SwiftData

/// Meeting metadata frozen onto a note at capture start. History queries run
/// on snapshots, so captured meetings survive calendar-event deletion.
@Model
final class MeetingSnapshot {
    var id: UUID = UUID()
    var title: String = ""
    /// Stable across occurrences of a recurring series.
    var seriesID: String = ""
    var occurrenceDate: Date = Date()
    var attendees: [String] = []

    /// Inverse of `ReviewNote.meetingSnapshot`. Optional for CloudKit.
    var note: ReviewNote?

    init(title: String = "", seriesID: String = "", occurrenceDate: Date = .now, attendees: [String] = []) {
        self.title = title
        self.seriesID = seriesID
        self.occurrenceDate = occurrenceDate
        self.attendees = attendees
    }
}
