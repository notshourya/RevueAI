import Foundation

/// Content for the first-run tour. Kept as plain data so the copy is testable
/// and the presentation layer (TourKit) stays swappable.
struct OnboardingPage: Identifiable {
    let id: Int
    let systemImage: String
    let title: String
    let subtitle: String

    /// Name of the pre-rendered slide artwork bundled as a resource
    /// (see `Tools/render-tour-art.swift`).
    var imageName: String { "tour_\(id)" }

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            systemImage: "circle.hexagongrid.fill",
            title: "Meet RevueAI",
            subtitle: "Your reviews, captured as structured notes — summaries, action items, and decisions, extracted live while you talk."
        ),
        OnboardingPage(
            id: 1,
            systemImage: "lock.shield.fill",
            title: "Nothing is ever recorded",
            subtitle: "Audio is transcribed on-device and discarded instantly. No recordings, no transcripts on disk — only the structured note survives."
        ),
        OnboardingPage(
            id: 2,
            systemImage: "mic.fill",
            title: "Microphone access",
            subtitle: "RevueAI listens through your mic to transcribe what you say. You'll grant this on the next screen."
        ),
        OnboardingPage(
            id: 3,
            systemImage: "person.2.wave.2.fill",
            title: "Hear Participants too",
            subtitle: "To capture the other side of Zoom, Meet, or Teams calls, RevueAI needs System Audio Recording — enabled in Privacy & Security."
        ),
        OnboardingPage(
            id: 4,
            systemImage: "waveform",
            title: "Start your first capture",
            subtitle: "Hit the orb when your next review starts. Stop when it ends — your note is ready seconds later."
        ),
    ]
}
