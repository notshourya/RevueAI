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
                Decision.self,
                Speaker.self,
                PlannedCapture.self,
                MeetingSnapshot.self,
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
            RootShellView()
                .environment(coordinator)
                .frame(minWidth: 980, minHeight: 560)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        .defaultSize(width: 1240, height: 720)

        MenuBarExtra {
            CapturePanelView()
                .environment(coordinator)
                .modelContainer(container)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        } label: {
            Image(systemName: coordinator.state == .listening ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .tint(Theme.accent)
        }
    }
}
