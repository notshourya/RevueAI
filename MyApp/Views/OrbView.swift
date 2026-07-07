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

/// Legacy capture identity wrapper. Visually this is now a reactive
/// glass-nanoparticle field, with the existing name preserved for call sites
/// and tests.
struct OrbView: View {
    let state: OrbState
    var size: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch state {
            case .idle:
                animatedOrDefault(mode: .idle)
            case .listening:
                animatedOrDefault(mode: .listening)
            case .extracting:
                animatedOrDefault(mode: .extracting)
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.warm.opacity(0.72), lineWidth: 2)
                            .blur(radius: 1.5)
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
                animatedOrDefault(mode: .danger)
                Image(systemName: "exclamationmark")
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: size * 0.20, style: .continuous)
                .fill(.white.opacity(0.015))
                .glassEffect(.regular.tint(stateColor.opacity(0.08)),
                             in: .rect(cornerRadius: size * 0.20))
                .frame(width: size * 0.88, height: size * 0.88)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func animatedOrDefault(mode: StateOrb.Mode) -> some View {
        if reduceMotion {
            staticParticleField(mode: mode)
        } else {
            StateOrb(mode: mode, size: size)
        }
    }

    private func staticParticleField(mode: StateOrb.Mode) -> some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                let start = particlePoint(index, mode: mode)
                let end = particlePoint(index + 7, mode: mode)
                Capsule()
                    .fill(particleColor(mode).opacity(0.16))
                    .frame(width: hypot(end.x - start.x, end.y - start.y), height: 1)
                    .rotationEffect(.radians(atan2(end.y - start.y, end.x - start.x)))
                    .position(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            }

            ForEach(0..<24, id: \.self) { index in
                let point = particlePoint(index, mode: mode)
                Circle()
                    .fill(
                        RadialGradient(colors: [.white.opacity(0.94),
                                                particleColor(mode).opacity(0.86),
                                                particleColor(mode).opacity(0.12)],
                                       center: UnitPoint(x: 0.32, y: 0.28),
                                       startRadius: 1,
                                       endRadius: point.diameter)
                    )
                    .frame(width: point.diameter, height: point.diameter)
                    .shadow(color: particleColor(mode).opacity(0.42), radius: point.diameter * 0.9)
                    .position(x: point.x, y: point.y)
            }
        }
        .frame(width: size, height: size)
    }

    private func particlePoint(_ index: Int, mode: StateOrb.Mode) -> (x: CGFloat, y: CGFloat, diameter: CGFloat) {
        let a = CGFloat((index * 37) % 100) / 100
        let b = CGFloat((index * 61 + 17) % 100) / 100
        let c = CGFloat((index * 29 + 43) % 100) / 100
        let expansion: CGFloat = switch mode {
        case .idle: 0.78
        case .listening: 0.90
        case .extracting: 0.98
        case .processing: 0.84
        case .danger: 0.88
        }
        let angle = a * .pi * 2
        let radius = b.squareRoot() * size * 0.36 * expansion
        let jitter = CGFloat(index % 3 - 1) * size * 0.012
        return (
            x: size / 2 + cos(angle) * radius + jitter,
            y: size / 2 + sin(angle) * radius - jitter,
            diameter: size * (0.035 + c * 0.030)
        )
    }

    private var stateColor: Color {
        switch state {
        case .idle, .listening: return Theme.accent
        case .extracting: return Theme.warm
        case .paused: return Theme.steel
        case .processing: return Theme.steel
        case .error: return Theme.danger
        }
    }

    private func particleColor(_ mode: StateOrb.Mode) -> Color {
        switch mode {
        case .idle, .listening: return Theme.accent
        case .extracting: return Theme.warm
        case .processing: return Theme.steel
        case .danger: return Theme.danger
        }
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
