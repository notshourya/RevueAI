import SwiftUI

/// A Siri-style flowing multicolor glow rendered by the `siriGlow` Metal shader
/// and driven by `TimelineView(.animation)`. Used for the live AI states:
/// listening (full color) and processing (cooler).
struct StateOrb: View {
    enum Mode {
        case listening
        case processing

        var shaderValue: Float { self == .processing ? 1 : 0 }
    }

    var mode: Mode
    var size: CGFloat = 120

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSince1970
                .truncatingRemainder(dividingBy: 86_400)
            Rectangle()
                .colorEffect(
                    ShaderLibrary.siriGlow(
                        .float2(Float(size), Float(size)),
                        .float(time),
                        .float(mode.shaderValue)
                    )
                )
                .frame(width: size, height: size)
                .blur(radius: size * 0.02)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
