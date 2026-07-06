import Foundation

/// Tracks where a `ReviewNote` sits in the capture → extraction → polish pipeline.
///
/// `String`-backed and `Codable` to keep the SwiftData schema CloudKit-ready.
enum ProcessingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Currently listening; live points are being checkpointed as they appear.
    case capturing
    /// The final polish pass is running.
    case processing
    /// Polished by the on-device model (offline / PCC-unavailable fallback).
    case processedOnDevice
    /// Polished by the preferred backend (Private Cloud Compute, when available).
    case polished

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .capturing: return "Capturing"
        case .processing: return "Processing"
        case .processedOnDevice: return "Processed on-device"
        case .polished: return "Polished"
        }
    }
}
