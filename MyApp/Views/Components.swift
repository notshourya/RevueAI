import SwiftUI

// MARK: - Design system (machined glass + liquid metal)

enum Theme {
    /// Primary accent: cold plasma over graphite, deliberately not purple.
    static let accent = Color(red: 0.18, green: 0.86, blue: 0.80)
    static let accentDeep = Color(red: 0.08, green: 0.46, blue: 0.50)
    static let steel = Color(red: 0.40, green: 0.55, blue: 0.62)
    static let warm = Color(red: 1.00, green: 0.64, blue: 0.28)
    static let success = Color(red: 0.35, green: 0.86, blue: 0.55)
    static let warning = Color(red: 1.00, green: 0.70, blue: 0.30)
    static let danger = Color(red: 1.00, green: 0.34, blue: 0.28)
    static let muted = Color(red: 0.58, green: 0.64, blue: 0.68)
    static let ink = Color(red: 0.025, green: 0.029, blue: 0.031)
    static let panel = Color(red: 0.075, green: 0.082, blue: 0.082)
    static let panelStroke = Color.white.opacity(0.08)

    /// Heated-metal gradient for primary actions and highlights.
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent,
                     Color(red: 0.22, green: 0.58, blue: 0.68),
                     warm],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static var dangerGradient: LinearGradient {
        LinearGradient(
            colors: [danger, Color(red: 0.82, green: 0.18, blue: 0.12), warm.opacity(0.85)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static let cardRadius: CGFloat = 8

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    /// Back-compat alias used around the app.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// A shader-backed graphite field. It gives the app a quiet metal substrate
/// without becoming a decorative wallpaper.
struct AppBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { context in
                let time = reduceMotion ? 0 : context.date.timeIntervalSince1970
                    .truncatingRemainder(dividingBy: 86_400)
                Rectangle()
                    .colorEffect(
                        ShaderLibrary.metalBackdrop(
                            .float2(Float(proxy.size.width), Float(proxy.size.height)),
                            .float(Float(time))
                        )
                    )
                    .overlay(alignment: .topLeading) {
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.18), .clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                        .blendMode(.screen)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        LinearGradient(
                            colors: [.clear, Theme.warm.opacity(0.10)],
                            startPoint: .center,
                            endPoint: .bottomTrailing
                        )
                        .blendMode(.screen)
                    }
            }
        }
        .background(Theme.ink)
        .ignoresSafeArea()
    }
}

/// Kept as the app-wide background name used across screens.
struct PremiumBackground: View {
    var body: some View { AppBackground() }
}

/// A frosted-glass surface — the workhorse container.
struct GlassCard<Content: View>: View {
    var radius: CGFloat = Theme.cardRadius
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .glassEffect(.regular.tint(Theme.panel.opacity(0.34)), in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.panelStroke, lineWidth: 1)
            )
    }
}

/// Back-compat: `Card` now renders as glass.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View { GlassCard(padding: padding) { content } }
}

// MARK: - Verdict

extension ReviewVerdict {
    var tint: Color {
        switch self {
        case .approved: return Theme.success
        case .needsChanges: return Theme.warning
        case .rejected: return Theme.danger
        case .pending: return Theme.muted
        }
    }
}

struct VerdictBadge: View {
    let verdict: ReviewVerdict
    var body: some View {
        Label(verdict.displayName, systemImage: verdict.systemImage)
            .font(Theme.rounded(12, .semibold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(verdict.tint.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(verdict.tint.opacity(0.35), lineWidth: 1))
            .foregroundStyle(verdict.tint)
    }
}

// MARK: - Priority & category

extension ActionPriority {
    var tint: Color {
        switch self {
        case .blocker: return Theme.danger
        case .major: return Theme.warning
        case .minor: return Color(red: 0.98, green: 0.88, blue: 0.4)
        case .nit: return Theme.muted
        }
    }
}

struct PriorityBadge: View {
    let priority: ActionPriority
    var body: some View {
        Text(priority.displayName.uppercased())
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(priority.tint.opacity(0.16), in: Capsule())
            .foregroundStyle(priority.tint)
    }
}

struct CategoryChip: View {
    let category: ActionCategory
    var body: some View {
        Label(category.displayName, systemImage: category.systemImage)
            .font(Theme.rounded(11, .medium))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Status pill

struct StatusPill: View {
    let text: String
    let color: Color
    var pulsing: Bool = false
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.9), radius: pulsing && pulse ? 5 : 0)
                .opacity(pulsing && pulse ? 0.4 : 1)
                .animation(pulsing ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: pulse)
            Text(text).font(Theme.rounded(12, .semibold))
        }
        .padding(.horizontal, 11).padding(.vertical, 5)
        .glassEffect(.regular.tint(color.opacity(0.20)), in: .capsule)
        .overlay(Capsule().strokeBorder(color.opacity(0.34), lineWidth: 1))
        .foregroundStyle(color)
        .onAppear { if pulsing { pulse = true } }
    }
}

// MARK: - Accent button

/// A glossy accent-gradient pill button used for primary actions.
struct AccentButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: LinearGradient = Theme.accentGradient
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(Theme.rounded(15, .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1))
            .foregroundStyle(Color(red: 0.02, green: 0.03, blue: 0.03))
            .shadow(color: Theme.accent.opacity(hovering ? 0.42 : 0.24), radius: hovering ? 14 : 8, y: 4)
            .scaleEffect(hovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: hovering)
        .onHover { hovering = $0 }
    }
}
