import SwiftUI

/// RevueAI's brand record control. The button uses the same custom
/// liquid-metal shader as the live orb so "start listening" feels like waking
/// the material rather than pressing a generic control.
struct RecordOrb: View {
    var isActive: Bool = false
    var size: CGFloat = 88
    var disabled: Bool = false
    var action: () -> Void

    @State private var pulse = false
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var main: Color {
        isActive ? Theme.danger : Theme.accent
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(main.opacity(0.32))
                    .blur(radius: size * 0.22)
                    .scaleEffect(pulse ? 1.18 : 0.92)

                if reduceMotion {
                    staticOrb
                } else {
                    StateOrb(mode: isActive ? .danger : .idle, size: size)
                }

                Circle()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    .frame(width: size * 0.84, height: size * 0.84)

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

    private var staticOrb: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .white.opacity(0.90),
                        main.opacity(0.88),
                        Theme.steel.opacity(0.62),
                        Theme.ink.opacity(0.98)
                    ],
                    center: UnitPoint(x: 0.34, y: 0.25),
                    startRadius: 1,
                    endRadius: size * 0.62
                )
            )
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.58), main.opacity(0.32), .white.opacity(0.06)],
                                   startPoint: .top,
                                   endPoint: .bottom),
                    lineWidth: 1.5
                )
            )
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.34))
                    .blur(radius: size * 0.07)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .offset(x: size * 0.12, y: size * 0.1)
            }
            .frame(width: size, height: size)
    }
}
