import Foundation

/// Which live illustration a slide renders (see SlideArtView). Live views
/// instead of pre-rendered art: always in sync with the design, adaptive
/// to light/dark.
enum SlideArt: String, CaseIterable {
    case orb, privacy, liveNote, ruler, assistant
}

/// Content for the first-run tour. Plain data so the copy is testable.
struct OnboardingPage: Identifiable, Equatable {
    let id: Int
    let art: SlideArt
    let title: String
    let subtitle: String

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: 0, art: .orb,
            title: "Meet RevueAI",
            subtitle: "Your reviews, captured as structured notes — summaries, action items, and decisions, extracted live while you talk."
        ),
        OnboardingPage(
            id: 1, art: .privacy,
            title: "Nothing is ever recorded",
            subtitle: "Audio is transcribed on-device and discarded instantly. No recordings, no transcripts on disk — only the structured note survives."
        ),
        OnboardingPage(
            id: 2, art: .liveNote,
            title: "Talk, and the note builds itself",
            subtitle: "Action items land on a board you can curate — complete, reorder, tag. Your edits always survive the AI's final polish."
        ),
        OnboardingPage(
            id: 3, art: .ruler,
            title: "Your meetings, on a ruler",
            subtitle: "Scrub your history like a timer dial, filter the library by day, and arm upcoming meetings to capture themselves."
        ),
        OnboardingPage(
            id: 4, art: .assistant,
            title: "Ask your notes anything",
            subtitle: "The search bar is an assistant: it answers from your reviews and cites the notes it used."
        ),
    ]
}
