import SwiftUI

// MARK: - Design system (native-neutral; identity lives in the orb only)

enum Theme {
    /// The app carries no brand color — it follows the user's system accent.
    /// Any visual identity belongs to the capture orb alone.
    static let accent = Color.accentColor
    static let accentDeep = Color.accentColor
    static let steel = Color.gray
    static let warm = Color.orange
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let muted = Color.secondary
    static let ink = Color(nsColor: .windowBackgroundColor)
    static let panel = Color.clear
    static let panelStroke = Color.clear

    /// Back-compat: primary actions are plain accent now, not gradients.
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [Color.accentColor], startPoint: .top, endPoint: .bottom)
    }

    static var dangerGradient: LinearGradient {
        LinearGradient(colors: [.red], startPoint: .top, endPoint: .bottom)
    }

    static let cardRadius: CGFloat = 10

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    /// Back-compat alias used around the app.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }
}

/// The plain native window background — no shader, no wallpaper.
struct AppBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
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
        .glassEffect(.regular, in: .capsule)
        .foregroundStyle(color)
        .onAppear { if pulsing { pulse = true } }
    }
}

// MARK: - Accent button

/// A standard prominent button for primary actions (native styling).
struct AccentButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: LinearGradient = Theme.accentGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(Theme.rounded(15, .semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
