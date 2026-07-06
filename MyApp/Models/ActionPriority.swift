import Foundation

/// How urgent an action item is, as judged during the review.
enum ActionPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case blocker
    case major
    case minor
    case nit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blocker: return "Blocker"
        case .major: return "Major"
        case .minor: return "Minor"
        case .nit: return "Nit"
        }
    }

    /// Lower is more urgent — used for sorting.
    var sortRank: Int {
        switch self {
        case .blocker: return 0
        case .major: return 1
        case .minor: return 2
        case .nit: return 3
        }
    }
}
