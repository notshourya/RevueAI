import SwiftUI

/// A reactive glass nanoparticle field rendered by a custom Metal shader and
/// driven by `TimelineView(.animation)`. The legacy type name is kept so the
/// rest of the app can share the same capture identity without churn.
struct StateOrb: View {
    enum Mode {
        case idle
        case listening
        case extracting
        case processing
        case danger

        var shaderValue: Float {
            switch self {
            case .idle: return 0
            case .listening: return 1
            case .extracting: return 2
            case .processing: return 3
            case .danger: return 4
            }
        }
    }

    var mode: Mode
    var size: CGFloat = 120

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSince1970
                .truncatingRemainder(dividingBy: 86_400)
            Rectangle()
                .colorEffect(
                    ShaderLibrary.nanoParticleCloud(
                        .float2(Float(size), Float(size)),
                        .float(time),
                        .float(mode.shaderValue)
                    )
                )
                .frame(width: size, height: size)
                .blur(radius: size * 0.004)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
