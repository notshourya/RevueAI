import SwiftUI
import SwiftData
import AppKit

/// The menu-bar capture surface — full glass, orb-centric, with real
/// pause/resume. Clean and focused: transcript/points hide behind "Details".
struct CapturePanelView: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @State private var showDetails = false

    var body: some View {
        @Bindable var coordinator = coordinator
        return VStack(spacing: 18) {
            header

            if !coordinator.modelAvailable {
                banner("Apple Intelligence is off — capture works, but summaries won't generate.",
                       icon: "sparkles", tint: .orange)
            }

            switch coordinator.state {
            case .listening, .paused: captureView
            case .processing:         processingView
            case .idle:               idleView(coordinator: coordinator)
            }

            if let error = coordinator.errorMessage, coordinator.state == .idle {
                banner(error, icon: "exclamationmark.triangle.fill", tint: .red)
            }
        }
        .padding(22)
        .frame(width: 340)
        .background(.ultraThinMaterial, in: ContainerRelativeShape())
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("RevueAI").font(Theme.display(20, .bold))
            Spacer()
            switch coordinator.state {
            case .idle:       StatusPill(text: "Ready", color: .secondary)
            case .listening:  StatusPill(text: "Listening", color: Color(red: 1, green: 0.42, blue: 0.44), pulsing: true)
            case .paused:     StatusPill(text: "Paused", color: .secondary)
            case .processing: StatusPill(text: "Summarizing", color: Color(red: 0.5, green: 0.6, blue: 1), pulsing: true)
            }
        }
    }

    // MARK: - Idle

    @ViewBuilder
    private func idleView(coordinator: CaptureCoordinator) -> some View {
        if coordinator.lastSummary != nil {
            summaryCard
            startButton(compact: true)
            participantsToggle
        } else {
            VStack(spacing: 18) {
                Text("Capture a review — RevueAI extracts prioritized action items with zero recording.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                startButton(compact: false)
                participantsToggle
            }
        }
    }

    private func startButton(compact: Bool) -> some View {
        Button(action: startAction) {
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                Text("Start Listening")
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(red: 1, green: 0.4, blue: 0.43).gradient, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var participantsToggle: some View {
        @Bindable var coordinator = coordinator
        return Toggle(isOn: $coordinator.captureSystemAudio) {
            Label("Capture participants", systemImage: "person.2.wave.2.fill")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(.accentColor)
    }

    // MARK: - Capture (listening / paused)

    private var captureView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.04))
                    .frame(width: 168, height: 168)
                StateOrb(mode: .listening, size: 148)
                    .opacity(coordinator.state == .paused ? 0.35 : 1)
                    .saturation(coordinator.state == .paused ? 0.3 : 1)
                if coordinator.state == .paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .animation(.smooth, value: coordinator.state)

            VStack(spacing: 4) {
                Text(coordinator.elapsedText)
                    .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Text("\(coordinator.capturedPhraseCount) phrases")
                    if coordinator.systemAudioActive {
                        Text("· you + participants")
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }

            controls

            detailsDisclosure
        }
    }

    private var controls: some View {
        HStack(spacing: 22) {
            if coordinator.state == .listening {
                RoundControl(icon: "pause.fill", action: pauseAction)
                    .help("Pause")
            } else {
                RoundControl(icon: "play.fill", tint: Color(red: 0.4, green: 0.85, blue: 0.55), action: resumeAction)
                    .help("Resume")
            }
            RoundControl(icon: "stop.fill", tint: Color(red: 1, green: 0.4, blue: 0.43), filled: true, action: stopAction)
                .help("Stop & summarize")
        }
    }

    @ViewBuilder
    private var detailsDisclosure: some View {
        if !coordinator.recentTranscript.isEmpty || !coordinator.livePoints.isEmpty {
            VStack(spacing: 10) {
                Button {
                    withAnimation(.smooth) { showDetails.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showDetails ? "Hide details" : "Details")
                        Image(systemName: "chevron.down").rotationEffect(.degrees(showDetails ? 180 : 0))
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if showDetails { detailsBody }
            }
        }
    }

    private var detailsBody: some View {
        VStack(spacing: 10) {
            if !coordinator.recentTranscript.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(coordinator.recentTranscript.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                    }
                    .frame(height: 80)
                    .onChange(of: coordinator.recentTranscript.count) {
                        withAnimation { proxy.scrollTo(coordinator.recentTranscript.count - 1, anchor: .bottom) }
                    }
                }
            }
            if !coordinator.livePoints.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(coordinator.livePoints.prefix(5), id: \.self) { point in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(.tertiary).frame(width: 4, height: 4).padding(.top, 6)
                            Text(point).font(.system(size: 13, design: .rounded))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 16) {
            StateOrb(mode: .processing, size: 110)
            Text("Summarizing your review…")
                .font(Theme.display(16, .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(coordinator.lastTitle ?? "Review")
                    .font(Theme.display(16, .semibold)).lineLimit(1)
                Spacer()
                if let verdict = coordinator.lastVerdict { VerdictBadge(verdict: verdict) }
            }
            if let summary = coordinator.lastSummary {
                Text(summary)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3).lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                openWindow(id: "library")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("Open in RevueAI", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Helpers

    private func banner(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.system(size: 12, design: .rounded)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func startAction() { Task { await coordinator.start(context: context) } }
    private func pauseAction() { Task { await coordinator.pause() } }
    private func resumeAction() { Task { await coordinator.resume() } }
    private func stopAction() { Task { await coordinator.stop() } }
}

/// A circular record-style control button.
private struct RoundControl: View {
    let icon: String
    var tint: Color = .white
    var filled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 56, height: 56)
                .background {
                    if filled {
                        Circle().fill(tint.gradient)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                        Circle().stroke(.white.opacity(0.14), lineWidth: 1)
                    }
                }
                .foregroundStyle(filled ? .white : tint)
        }
        .buttonStyle(.plain)
    }
}
