import Foundation

/// The outcome of a review, as determined during the final polish pass.
///
/// Stored as a `String`-backed, `Codable` enum so the schema stays
/// CloudKit-compatible (CloudKit mirroring supports `RawRepresentable`
/// `Codable` values with a default).
enum ReviewVerdict: String, Codable, CaseIterable, Identifiable, Sendable {
    case approved
    case needsChanges
    case rejected
    /// Set while a review is still being captured or has not been polished yet.
    case pending

    var id: String { rawValue }

    /// Human-readable label for display in the UI.
    var displayName: String {
        switch self {
        case .approved: return "Approved"
        case .needsChanges: return "Needs changes"
        case .rejected: return "Rejected"
        case .pending: return "Pending"
        }
    }

    /// SF Symbol used to represent the verdict.
    var systemImage: String {
        switch self {
        case .approved: return "checkmark.seal.fill"
        case .needsChanges: return "exclamationmark.triangle.fill"
        case .rejected: return "xmark.seal.fill"
        case .pending: return "hourglass"
        }
    }
}
