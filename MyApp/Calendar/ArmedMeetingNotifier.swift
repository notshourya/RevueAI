import Foundation
import SwiftData
import UserNotifications

/// Schedules "your armed meeting started — start listening?" notifications
/// and routes the Start action back into the app. Listening never begins
/// without the user tapping Start (here or in the in-app prompt card).
@MainActor
final class ArmedMeetingNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let categoryID = "ARMED_MEETING"
    static let startActionID = "START_CAPTURE"

    /// Called with the planned capture when the user taps Start.
    var onStartRequested: ((PlannedCapture) -> Void)?

    private var modelContext: ModelContext?

    func activate(context: ModelContext) {
        modelContext = context
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: Self.startActionID,
                                         title: "Start listening",
                                         options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.categoryID,
                                              actions: [start],
                                              intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    func ensureAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Builds the notification for one planned capture. Identifier is stable
    /// per occurrence so re-syncing replaces rather than duplicates.
    static func request(for planned: PlannedCapture) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "RevueAI"
        content.body = "\(planned.title) started — start listening?"
        content.categoryIdentifier = categoryID
        content.userInfo = [
            "eventID": planned.eventID,
            "occurrence": planned.occurrenceDate.timeIntervalSince1970,
        ]
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: planned.occurrenceDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "armed-\(planned.eventID)-\(Int(planned.occurrenceDate.timeIntervalSince1970))"
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    /// Reconciles pending notifications with the current set of planned
    /// captures (call after arm/disarm changes and on launch).
    func sync(with context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        let planned = (try? context.fetch(FetchDescriptor<PlannedCapture>())) ?? []
        let wanted = planned.filter { $0.occurrenceDate > .now }
        center.removeAllPendingNotificationRequests()
        for capture in wanted {
            center.add(Self.request(for: capture))
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard response.actionIdentifier == Self.startActionID,
              let eventID = info["eventID"] as? String,
              let occurrence = info["occurrence"] as? TimeInterval else { return }
        await MainActor.run {
            guard let context = modelContext,
                  let planned = CapturePlanner.consumeMatch(
                      eventID: eventID,
                      occurrence: Date(timeIntervalSince1970: occurrence),
                      in: context
                  ) else { return }
            onStartRequested?(planned)
        }
    }
}

extension CapturePlanner {
    /// Consume by raw ids (notification payload) — tolerant of sub-second
    /// date drift from the round-trip through userInfo.
    @discardableResult
    static func consumeMatch(eventID: String, occurrence: Date, in context: ModelContext) -> PlannedCapture? {
        let all = (try? context.fetch(FetchDescriptor<PlannedCapture>())) ?? []
        guard let planned = all.first(where: {
            $0.eventID == eventID && abs($0.occurrenceDate.timeIntervalSince(occurrence)) < 2
        }) else { return nil }
        let copy = PlannedCapture(eventID: planned.eventID, seriesID: planned.seriesID,
                                  occurrenceDate: planned.occurrenceDate, title: planned.title)
        context.delete(planned)
        try? context.save()
        return copy
    }
}
