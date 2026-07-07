import SwiftUI

/// The orb's visual state — a pure mapping from coordinator state so it can
/// be unit-tested and shared by every orb surface (live panel, menu bar,
/// floating window).
enum OrbState: Equatable {
    case idle
    case listening
    case paused
    case extracting
    case processing
    case error

    /// An error only shows on the orb once capture is fully stopped; during
    /// capture the orb keeps signalling that listening continues.
    static func from(captureState: CaptureCoordinator.State, isExtracting: Bool, hasError: Bool) -> OrbState {
        switch captureState {
        case .idle: return hasError ? .error : .idle
        case .paused: return .paused
        case .processing: return .processing
        case .listening: return isExtracting ? .extracting : .listening
        }
    }
}

/// The brand orb, rendered per state: shader glow while the AI is live,
/// static gradient when idle, dimmed when paused, grey on error. Respects
/// Reduce Motion by dropping the animated shader for a static gradient.
struct OrbView: View {
    let state: OrbState
    var size: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch state {
            case .idle:
                staticOrb(colors: [Theme.accent.opacity(0.9), Theme.accent.opacity(0.5)])
            case .listening:
                animatedOrDefault(mode: .listening)
            case .extracting:
                animatedOrDefault(mode: .listening)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.7), lineWidth: 2)
                            .blur(radius: 2)
                            .frame(width: size * 0.9, height: size * 0.9)
                    )
            case .paused:
                animatedOrDefault(mode: .listening)
                    .opacity(0.35)
                    .saturation(0.3)
                Image(systemName: "pause.fill")
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            case .processing:
                animatedOrDefault(mode: .processing)
            case .error:
                staticOrb(colors: [Color(white: 0.45), Color(white: 0.25)])
                Image(systemName: "exclamationmark")
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func animatedOrDefault(mode: StateOrb.Mode) -> some View {
        if reduceMotion {
            staticOrb(colors: mode == .processing
                      ? [Color(red: 0.36, green: 0.52, blue: 1.0), Theme.accent.opacity(0.6)]
                      : [Theme.accent, Color(red: 0.92, green: 0.42, blue: 0.78).opacity(0.7)])
        } else {
            StateOrb(mode: mode, size: size)
        }
    }

    private func staticOrb(colors: [Color]) -> some View {
        Circle()
            .fill(
                RadialGradient(colors: colors,
                               center: UnitPoint(x: 0.36, y: 0.30),
                               startRadius: 1,
                               endRadius: size * 0.62)
            )
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.04)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.5
                )
            )
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.3))
                    .blur(radius: size * 0.07)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .offset(x: size * 0.12, y: size * 0.1)
            }
            .frame(width: size * 0.86, height: size * 0.86)
    }

    private var accessibilityText: String {
        switch state {
        case .idle: "Idle"
        case .listening: "Listening"
        case .paused: "Paused"
        case .extracting: "Listening, extracting points"
        case .processing: "Summarizing"
        case .error: "Capture error"
        }
    }
}
