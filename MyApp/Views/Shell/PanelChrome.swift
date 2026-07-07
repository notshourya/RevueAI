import SwiftUI

/// Standard chrome for one shell panel: a slim header (icon label, optional
/// accessory, collapse control) over the panel's content, on one glass
/// surface. Falls back to an opaque fill when transparency is reduced.
struct PanelChrome<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    var onCollapse: () -> Void
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(Theme.rounded(12, .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                accessory
                Button(action: onCollapse) {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(90))
                }
                .buttonStyle(.plain)
                .help("Collapse panel")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .modifier(PanelSurface(reduceTransparency: reduceTransparency))
    }
}

/// Glass panel surface with an opaque accessibility fallback.
private struct PanelSurface: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(white: 0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    )
            )
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }
}
