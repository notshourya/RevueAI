import SwiftUI
import SwiftData

/// RevueAI — captures technical reviews as structured, actionable notes with
/// zero audio recording. A main library window plus an always-available
/// menu-bar capture companion.
@main
struct RevueAIApp: App {
    @State private var coordinator = CaptureCoordinator()
    private let container: ModelContainer

    init() {
        do {
            let schema = Schema([
                ReviewNote.self,
                ActionItem.self,
                OpenQuestion.self,
                Speaker.self,
            ])
            // Local store for Milestone 1. The schema is CloudKit-ready, so
            // enabling iCloud sync later is a configuration change (add the
            // iCloud capability and a `.automatic` CloudKit database), not a
            // migration.
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup(id: "library") {
            LibraryView()
                .environment(coordinator)
                .frame(minWidth: 720, minHeight: 460)
        }
        .modelContainer(container)
        .defaultSize(width: 900, height: 600)

        MenuBarExtra {
            CapturePanelView()
                .environment(coordinator)
                .modelContainer(container)
        } label: {
            Image(systemName: coordinator.state == .listening ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
