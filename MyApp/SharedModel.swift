import Foundation
import SwiftData

/// The app's single model container — shared by the UI scene and App
/// Intents so Siri answers from the same store.
enum SharedModel {
    static let container: ModelContainer = {
        let schema = Schema([
            ReviewNote.self,
            ActionItem.self,
            OpenQuestion.self,
            Decision.self,
            Speaker.self,
            PlannedCapture.self,
            MeetingSnapshot.self,
        ])
        // Local store for Milestone 1. The schema is CloudKit-ready, so
        // enabling iCloud sync later is a configuration change, not a migration.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
