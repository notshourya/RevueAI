import SwiftUI
import AVFoundation
import TourKit

/// First-run flow: the TourKit slideshow (brand + privacy story), then a
/// guided permissions step, ending in "start your first capture". Skippable
/// at any point; re-runnable from Settings. Never blocks capture — closing
/// the sheet always leaves the app fully usable.
struct OnboardingSheet: View {
    @Binding var isPresented: Bool
    var onStartCapture: () -> Void

    private enum Phase { case tour, permissions }
    @State private var phase: Phase = .tour
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    var body: some View {
        Group {
            switch phase {
            case .tour: tourPhase
            case .permissions: permissionsPhase
            }
        }
        .background(Color(white: 0.07))
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    // MARK: - Tour

    private var tourPhase: some View {
        TourSlideshowView(
            pages: OnboardingPage.all.map { page in
                TourPage(
                    imageName: page.imageName,
                    imageBundle: .main,
                    title: LocalizedStringKey(page.title),
                    description: LocalizedStringKey(page.subtitle)
                )
            },
            width: 520,
            finishButtonTitle: "Set up permissions",
            onFinish: {
                withAnimation(.smooth) { phase = .permissions }
            },
            onClose: { finish() }
        )
        .padding(16)
    }

    // MARK: - Permissions

    private var permissionsPhase: some View {
        VStack(alignment: .leading, spacing: 18) {
            OrbView(state: .idle, size: 72)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

            Text("Two permissions, full privacy")
                .font(Theme.display(20))
                .frame(maxWidth: .infinity)

            permissionRow(
                icon: "mic.fill",
                title: "Microphone",
                detail: "Transcribes your side on-device.",
                done: micGranted
            ) {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in micGranted = granted }
                }
            }

            permissionRow(
                icon: "person.2.wave.2.fill",
                title: "System Audio Recording",
                detail: "Captures participants in online meetings. Opens Privacy & Security — enable RevueAI there.",
                done: false
            ) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }

            Spacer()

            HStack {
                Button("Done") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Start my first capture") {
                    finish()
                    onStartCapture()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 552, height: 480)
    }

    private func permissionRow(icon: String, title: String, detail: String, done: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.rounded(14, .semibold))
                Text(detail).font(Theme.rounded(11)).foregroundStyle(.secondary)
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.55))
            } else {
                Button("Enable", action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func finish() {
        isPresented = false
    }
}
