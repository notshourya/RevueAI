import SwiftUI
import SwiftData

/// The live-capture panel: the orb, the elapsed timer, transport controls,
/// and points streaming in as the live pass extracts them.
struct LivePanelView: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                orb
                status
                if coordinator.isActive || coordinator.state == .processing { transport }
                if !coordinator.livePoints.isEmpty { pointsList }
                if !coordinator.recentTranscript.isEmpty && coordinator.isActive { transcriptTicker }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Orb + status

    @ViewBuilder
    private var orb: some View {
        if coordinator.state == .idle {
            RecordOrb(isActive: false, size: 84) {
                Task { await coordinator.start(context: context) }
            }
            .padding(.top, 20)
        } else {
            OrbView(state: OrbState.from(captureState: coordinator.state,
                                         isExtracting: coordinator.isExtracting,
                                         hasError: coordinator.errorMessage != nil),
                    size: 132)
                .padding(.top, 12)
        }
    }

    private var status: some View {
        VStack(spacing: 4) {
            switch coordinator.state {
            case .idle:
                Text("Ready to listen")
                    .font(Theme.rounded(13, .medium))
                    .foregroundStyle(.secondary)
            case .processing:
                Text("Summarizing your review…")
                    .font(Theme.rounded(13, .medium))
                    .foregroundStyle(.secondary)
            case .listening, .paused:
                Text(coordinator.elapsedText)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("\(coordinator.capturedPhraseCount) phrases\(coordinator.systemAudioActive ? " · you + participants" : "")")
                    .font(Theme.rounded(12, .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 16) {
            if coordinator.state == .listening {
                transportButton("pause.fill", help: "Pause") { await coordinator.pause() }
            } else if coordinator.state == .paused {
                transportButton("play.fill", help: "Resume") { await coordinator.resume() }
            }
            if coordinator.isActive {
                transportButton("stop.fill", help: "Stop & summarize") { await coordinator.stop() }
            }
        }
    }

    private func transportButton(_ icon: String, help: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Circle())
        .help(help)
    }

    // MARK: - Live points

    private var pointsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Points so far", systemImage: "sparkles")
                .font(Theme.rounded(11, .bold))
                .foregroundStyle(.secondary)
            ForEach(coordinator.livePoints, id: \.self) { point in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(.tertiary).frame(width: 4, height: 4).padding(.top, 6)
                    Text(point)
                        .font(Theme.rounded(13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Transcript ticker

    private var transcriptTicker: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(coordinator.recentTranscript.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(Theme.rounded(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(10)
            }
            .frame(height: 96)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .onChange(of: coordinator.recentTranscript.count) {
                withAnimation { proxy.scrollTo(coordinator.recentTranscript.count - 1, anchor: .bottom) }
            }
        }
    }
}
