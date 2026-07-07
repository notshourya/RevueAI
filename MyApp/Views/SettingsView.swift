import SwiftUI

/// App settings: floating orb, participants capture, and the welcome tour.
struct SettingsView: View {
    @AppStorage("floatingOrbEnabled") private var floatingOrbEnabled = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Show floating orb while listening", isOn: $floatingOrbEnabled)
            }
            Section("Help") {
                Button("Show Welcome Tour") {
                    hasCompletedOnboarding = false
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                Text("The tour reopens in the main window.")
                    .font(Theme.rounded(11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background { PremiumBackground() }
        .tint(Theme.accent)
        .frame(width: 380)
        .preferredColorScheme(.dark)
    }
}
