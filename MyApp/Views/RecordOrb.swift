import SwiftUI

/// RevueAI's brand record control — a glossy, softly-breathing orb. Tap to
/// start (accent) or stop (red) a capture. Used in the menu-bar panel and the
/// main app so the gesture feels the same everywhere.
struct RecordOrb: View {
    var isActive: Bool = false
    var size: CGFloat = 88
    var disabled: Bool = false
    var action: () -> Void

    @State private var pulse = false
    @State private var hover = false

    private var main: Color {
        isActive ? Color(red: 1.0, green: 0.4, blue: 0.43) : Theme.accent
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Soft outer bloom that gently breathes.
                Circle()
                    .fill(main.opacity(0.32))
                    .blur(radius: size * 0.22)
                    .scaleEffect(pulse ? 1.18 : 0.92)

                // Orb body.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [main.opacity(1.0), main.opacity(0.72), main.opacity(0.92)],
                            center: UnitPoint(x: 0.36, y: 0.30),
                            startRadius: 1,
                            endRadius: size * 0.62
                        )
                    )
                    .overlay(
                        Circle().strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.04)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1.5
                        )
                    )
                    // Specular highlight.
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(.white.opacity(0.3))
                            .blur(radius: size * 0.07)
                            .frame(width: size * 0.34, height: size * 0.34)
                            .offset(x: size * 0.12, y: size * 0.1)
                    }
                    .frame(width: size, height: size)

                // Center glyph: record dot / stop square.
                Group {
                    if isActive {
                        RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
                            .fill(.white)
                            .frame(width: size * 0.26, height: size * 0.26)
                    } else {
                        Circle()
                            .fill(.white)
                            .frame(width: size * 0.22, height: size * 0.22)
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 2)
            }
            .frame(width: size * 1.4, height: size * 1.4)
            .scaleEffect(hover && !disabled ? 1.06 : 1)
            .shadow(color: main.opacity(0.45), radius: hover ? 22 : 14, y: 4)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { isHovering in
            withAnimation(.spring(duration: 0.25)) { hover = isHovering }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel(isActive ? "Stop capture" : "Start listening")
    }
}
