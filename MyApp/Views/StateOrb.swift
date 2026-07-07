import SwiftUI

/// The liquid glass blob — RevueAI's capture identity, rendered by the
/// `liquidGlassBlob` Metal shader. The legacy type name is kept so the rest
/// of the app shares the same identity without churn. Pass `animated: false`
/// for a frozen frame (Reduce Motion).
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
    var animated: Bool = true

    var body: some View {
        if animated {
            TimelineView(.animation) { context in
                blob(time: context.date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400))
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else {
            blob(time: 12.0)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    private func blob(time: TimeInterval) -> some View {
        Rectangle()
            .colorEffect(
                ShaderLibrary.liquidGlassBlob(
                    .float2(Float(size), Float(size)),
                    .float(Float(time)),
                    .float(mode.shaderValue)
                )
            )
            .frame(width: size, height: size)
    }
}
