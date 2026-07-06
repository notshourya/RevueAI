import SwiftUI

// MARK: - Design system (Raycast / Arc — playful-premium glass)

enum Theme {
    /// Primary accent.
    static let accent = Color(red: 0.58, green: 0.47, blue: 1.0)

    /// Vibrant accent gradient for primary actions & highlights.
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.36, green: 0.52, blue: 1.0),
                     Color(red: 0.62, green: 0.40, blue: 1.0),
                     Color(red: 0.92, green: 0.42, blue: 0.78)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static let cardRadius: CGFloat = 18

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    /// Back-compat alias used around the app.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// A soft, colorful animated mesh backdrop — the signature surface everything
/// glass floats over. Dark enough to keep content legible, alive with slow
/// motion for a little delight.
struct AppBackground: View {
    var body: some View {
        Color(white: 0.08).ignoresSafeArea()
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
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
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
        case .approved: return Color(red: 0.35, green: 0.9, blue: 0.6)
        case .needsChanges: return Color(red: 1.0, green: 0.72, blue: 0.32)
        case .rejected: return Color(red: 1.0, green: 0.42, blue: 0.5)
        case .pending: return Color(red: 0.6, green: 0.62, blue: 0.72)
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
        case .blocker: return Color(red: 1.0, green: 0.42, blue: 0.5)
        case .major: return Color(red: 1.0, green: 0.72, blue: 0.32)
        case .minor: return Color(red: 0.98, green: 0.88, blue: 0.4)
        case .nit: return Color(red: 0.6, green: 0.62, blue: 0.72)
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
        .glassEffect(.regular.tint(color.opacity(0.28)), in: .capsule)
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
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .foregroundStyle(.white)
            .shadow(color: Theme.accent.opacity(hovering ? 0.5 : 0.3), radius: hovering ? 14 : 8, y: 4)
            .scaleEffect(hovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: hovering)
        .onHover { hovering = $0 }
    }
}
