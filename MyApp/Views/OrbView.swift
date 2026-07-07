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

/// The capture identity: a liquid glass blob driven by the shared state
/// machine. Reduce Motion freezes the material instead of animating it.
struct OrbView: View {
    let state: OrbState
    var size: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch state {
            case .idle:
                blob(.idle)
            case .listening:
                blob(.listening)
            case .extracting:
                blob(.extracting)
            case .paused:
                blob(.listening)
                    .opacity(0.35)
                    .saturation(0.3)
                Image(systemName: "pause.fill")
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            case .processing:
                blob(.processing)
            case .error:
                blob(.danger)
                Image(systemName: "exclamationmark")
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityText)
    }

    private func blob(_ mode: StateOrb.Mode) -> some View {
        StateOrb(mode: mode, size: size, animated: !reduceMotion)
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
