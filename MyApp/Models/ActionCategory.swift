import Foundation

/// The kind of work an action item represents.
enum ActionCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case bug
    case refactor
    case performance
    case security
    case testing
    case design
    case documentation
    case question
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bug: return "Bug"
        case .refactor: return "Refactor"
        case .performance: return "Performance"
        case .security: return "Security"
        case .testing: return "Testing"
        case .design: return "Design"
        case .documentation: return "Docs"
        case .question: return "Question"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .bug: return "ladybug"
        case .refactor: return "arrow.triangle.2.circlepath"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .security: return "lock.shield"
        case .testing: return "checklist"
        case .design: return "paintbrush.pointed"
        case .documentation: return "text.book.closed"
        case .question: return "questionmark.circle"
        case .other: return "circle.grid.2x2"
        }
    }
}
