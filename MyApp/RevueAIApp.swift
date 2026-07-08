import SwiftUI
import SwiftData

/// RevueAI — captures technical reviews as structured, actionable notes with
/// zero audio recording. A main library window plus an always-available
/// menu-bar capture companion.
@main
struct RevueAIApp: App {
    @State private var coordinator = CaptureCoordinator()

    var body: some Scene {
        WindowGroup(id: "library") {
            RootShellView()
                .environment(coordinator)
                .frame(minWidth: 980, minHeight: 560)
                .tint(Theme.accent)
                .fontDesign(.monospaced)
        }
        .modelContainer(SharedModel.container)
        .defaultSize(width: 1240, height: 720)

        MenuBarExtra {
            CapturePanelView()
                .environment(coordinator)
                .modelContainer(SharedModel.container)
                .tint(Theme.accent)
                .fontDesign(.monospaced)
        } label: {
            Image(systemName: coordinator.state == .listening ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .tint(Theme.accent)
                .fontDesign(.monospaced)
        }
    }
}
