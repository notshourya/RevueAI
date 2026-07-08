import SwiftUI
import AVFoundation

/// First-run flow: a paged glass slideshow of live slides, then a guided
/// permissions step, ending in "start your first capture". Skippable at
/// any point; re-runnable from Settings. Never blocks capture — closing
/// the sheet always leaves the app fully usable.
struct OnboardingSheet: View {
    @Binding var isPresented: Bool
    var onStartCapture: () -> Void

    private enum Phase { case tour, permissions }
    @State private var phase: Phase = .tour
    @State private var pageIndex = 0
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    private var page: OnboardingPage { OnboardingPage.all[pageIndex] }
    private var isLastPage: Bool { pageIndex == OnboardingPage.all.count - 1 }

    var body: some View {
        Group {
            switch phase {
            case .tour: tourPhase
            case .permissions: permissionsPhase
            }
        }
        .frame(width: 560, height: 540)
        .background { PremiumBackground() }
    }

    // MARK: - Slides

    private var tourPhase: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding([.top, .horizontal], 16)

            Spacer()

            SlideArtView(art: page.art)
                .frame(height: 210)
                .id(page.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))

            VStack(spacing: 8) {
                Text(page.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(page.subtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 400)
            }
            .padding(.top, 18)
            .animation(.smooth, value: pageIndex)

            Spacer()

            dots.padding(.bottom, 16)

            HStack {
                if pageIndex > 0 {
                    Button("Back") { withAnimation(.smooth) { pageIndex -= 1 } }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isLastPage ? "Set up permissions" : "Continue") {
                    withAnimation(.smooth) {
                        if isLastPage { phase = .permissions } else { pageIndex += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingPage.all) { candidate in
                Circle()
                    .fill(candidate.id == pageIndex ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                    .frame(width: 7, height: 7)
                    .onTapGesture { withAnimation(.smooth) { pageIndex = candidate.id } }
            }
        }
    }

    // MARK: - Permissions

    private var permissionsPhase: some View {
        VStack(alignment: .leading, spacing: 18) {
            OrbView(state: .idle, size: 72)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

            Text("Two permissions, full privacy")
                .font(.system(size: 20, weight: .bold, design: .rounded))
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
    }

    private func permissionRow(icon: String, title: String, detail: String,
                               done: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(detail).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
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
