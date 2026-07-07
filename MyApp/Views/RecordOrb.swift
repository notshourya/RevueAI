import SwiftUI

/// RevueAI's record control — the same liquid glass material as the live
/// blob, so "start listening" feels like waking the material rather than
/// pressing a generic control.
struct RecordOrb: View {
    var isActive: Bool = false
    var size: CGFloat = 88
    var disabled: Bool = false
    var action: () -> Void

    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                StateOrb(mode: isActive ? .danger : .idle, size: size, animated: !reduceMotion)

                Group {
                    if isActive {
                        RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
                            .fill(.white)
                            .frame(width: size * 0.22, height: size * 0.22)
                    } else {
                        Circle()
                            .fill(.white.opacity(0.92))
                            .frame(width: size * 0.18, height: size * 0.18)
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 2)
            }
            .frame(width: size * 1.2, height: size * 1.2)
            .scaleEffect(hover && !disabled ? 1.05 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { isHovering in
            withAnimation(.spring(duration: 0.25)) { hover = isHovering }
        }
        .accessibilityLabel(isActive ? "Stop capture" : "Start listening")
    }
}
