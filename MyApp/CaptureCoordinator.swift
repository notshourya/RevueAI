import Foundation
import SwiftData
import Observation

/// Owns a capture session end-to-end and drives the pipeline:
/// transcription → attribution → rolling transcript → periodic live extraction
/// (checkpointed to SwiftData) → final polish on stop.
///
/// Supports pause/resume: pausing halts transcription (releases the mic + tap)
/// and freezes the timer; resuming restarts capture and continues the same note.
@MainActor
@Observable
final class CaptureCoordinator {
    enum State: Equatable {
        case idle
        case listening
        case paused
        case processing
    }

    private(set) var state: State = .idle
    private(set) var livePoints: [String] = []
    private(set) var capturedPhraseCount = 0
    private(set) var elapsedSeconds = 0
    private(set) var recentTranscript: [String] = []
    private(set) var errorMessage: String?
    private(set) var modelAvailable: Bool
    var captureSystemAudio = true
    private(set) var systemAudioActive = false

    /// True while a live-extraction call is in flight — drives the orb's
    /// extracting shimmer. Purely observational; no pipeline behavior changes.
    private(set) var isExtracting = false

    // Result of the most recent completed session, for the panel's summary card.
    private(set) var lastSummary: String?
    private(set) var lastVerdict: ReviewVerdict?
    private(set) var lastTitle: String?

    /// mm:ss form of `elapsedSeconds`.
    var elapsedText: String {
        String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    var isActive: Bool { state == .listening || state == .paused }

    private let transcription: any TranscriptionProviding
    private let systemTranscription: any TranscriptionProviding
    private let attribution: SpeakerAttribution
    private let liveExtractor: LiveExtractor
    private let finalPolisher: FinalPolisher
    private let model: any ReviewLanguageModel

    private var transcript = RollingTranscript()
    private var currentNote: ReviewNote?
    private var modelContext: ModelContext?

    // Segmented timer: accumulated seconds from finished listening segments,
    // plus the current segment's start (nil while paused/stopped).
    private var accumulatedSeconds = 0
    private var segmentStartedAt: Date?

    private var streamTask: Task<Void, Never>?
    private var systemStreamTask: Task<Void, Never>?
    private var cadenceTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    private let firstExtractionDelay: Duration = .seconds(12)
    private let extractionInterval: Duration = .seconds(20)
    private let extractionSegmentThreshold = 6
    private let cadenceTick: Duration = .seconds(2)

    /// Whether the most recent live-extraction attempt threw — suppresses the
    /// cadence's threshold shortcut so failures retry at interval pacing.
    private var lastExtractionFailed = false

    init(
        transcription: (any TranscriptionProviding)? = nil,
        systemTranscription: (any TranscriptionProviding)? = nil,
        attribution: SpeakerAttribution = StreamOfOriginAttribution(),
        model: any ReviewLanguageModel = ReviewModelFactory.make()
    ) {
        self.transcription = transcription ?? SpeechTranscriptionService()
        self.systemTranscription = systemTranscription ?? SystemAudioTapService()
        self.attribution = attribution
        self.liveExtractor = LiveExtractor(model: model)
        self.finalPolisher = FinalPolisher(model: model)
        self.model = model
        self.modelAvailable = model.isAvailable
    }

    // MARK: - Lifecycle

    func start(context: ModelContext) async {
        guard state == .idle else { return }
        errorMessage = nil
        lastExtractionFailed = false
        livePoints = []
        capturedPhraseCount = 0
        elapsedSeconds = 0
        accumulatedSeconds = 0
        segmentStartedAt = nil
        recentTranscript = []
        lastSummary = nil
        lastVerdict = nil
        lastTitle = nil
        transcript = RollingTranscript()
        modelContext = context
        model.prewarm()

        let note = ReviewNote(title: Self.defaultTitle(), date: .now, status: .capturing)
        context.insert(note)
        try? context.save()
        currentNote = note

        await beginListening()
    }

    func pause() async {
        guard state == .listening else { return }
        finishSegment()
        elapsedSeconds = accumulatedSeconds
        await teardownStreams()
        await runLiveExtraction()   // checkpoint what we have so far
        state = .paused
    }

    func resume() async {
        guard state == .paused else { return }
        await beginListening()
    }

    func stop() async {
        guard isActive, let context = modelContext else { return }
        finishSegment()
        state = .processing
        await teardownStreams()
        await runLiveExtraction()

        if let note = currentNote {
            note.durationSeconds = Double(accumulatedSeconds)
            if transcript.isEmpty {
                note.summary = "No speech was captured in this session."
                note.status = .processedOnDevice
                try? context.save()
            } else if modelAvailable {
                await finalPolisher.polish(note: note, segments: transcript.segments, context: context)
            } else {
                note.summary = "Captured, but Apple Intelligence is off — turn it on to summarize."
                note.status = .processedOnDevice
                try? context.save()
            }
            lastTitle = note.title
            lastSummary = note.summary
            lastVerdict = note.verdict
            livePoints = note.sortedActionItems.map(\.oneLiner)
                + note.sortedDecisions.map { "✓ \($0.statement)" }
                + note.sortedOpenQuestions.map { "? \($0.text)" }
        }

        transcript.clear()
        recentTranscript = []
        currentNote = nil
        accumulatedSeconds = 0
        state = .idle
    }

    // MARK: - Capture plumbing

    private func beginListening() async {
        do {
            let micStream = try await transcription.start()
            streamTask = consume(micStream, origin: .microphone)

            systemAudioActive = false
            if captureSystemAudio {
                do {
                    let systemStream = try await systemTranscription.start()
                    systemStreamTask = consume(systemStream, origin: .systemAudio)
                    systemAudioActive = true
                } catch {
                    errorMessage = error.localizedDescription
                }
            }

            segmentStartedAt = .now
            state = .listening
            startCadence()
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
            state = accumulatedSeconds > 0 ? .paused : .idle
        }
    }

    private func teardownStreams() async {
        cadenceTask?.cancel(); cadenceTask = nil
        timerTask?.cancel(); timerTask = nil
        await transcription.stop()
        if systemAudioActive { await systemTranscription.stop() }
        _ = await streamTask?.value
        _ = await systemStreamTask?.value
        streamTask = nil
        systemStreamTask = nil
        systemAudioActive = false
    }

    private func finishSegment() {
        if let started = segmentStartedAt {
            accumulatedSeconds += Int(Date.now.timeIntervalSince(started))
        }
        segmentStartedAt = nil
    }

    /// Hybrid trigger: a burst of new segments extracts immediately; otherwise
    /// the interval flushes whatever trickled in. Silence costs nothing.
    /// After a failed attempt the threshold shortcut is suppressed (failure
    /// leaves pending high, and without this the cadence would retry every
    /// tick); retries fall back to interval pacing.
    nonisolated static func shouldExtract(
        pending: Int,
        elapsedSinceLastRun: Duration,
        threshold: Int,
        interval: Duration,
        lastAttemptFailed: Bool = false
    ) -> Bool {
        guard pending > 0 else { return false }
        if lastAttemptFailed { return elapsedSinceLastRun >= interval }
        return pending >= threshold || elapsedSinceLastRun >= interval
    }

    private func startCadence() {
        cadenceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.firstExtractionDelay)
            var lastRun = ContinuousClock.now
            while !Task.isCancelled {
                if Self.shouldExtract(
                    pending: self.transcript.pendingCount,
                    elapsedSinceLastRun: ContinuousClock.now - lastRun,
                    threshold: self.extractionSegmentThreshold,
                    interval: self.extractionInterval,
                    lastAttemptFailed: self.lastExtractionFailed
                ) {
                    await self.runLiveExtraction()
                    lastRun = ContinuousClock.now
                }
                try? await Task.sleep(for: self.cadenceTick)
            }
        }
    }

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let started = self.segmentStartedAt else { break }
                self.elapsedSeconds = self.accumulatedSeconds + Int(Date.now.timeIntervalSince(started))
            }
        }
    }

    private func consume(_ stream: AsyncThrowingStream<String, Error>, origin: StreamOrigin) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            do {
                for try await phrase in stream {
                    let segment = self.attribution.attribute(text: phrase, origin: origin, at: .now)
                    self.transcript.append(segment)
                    self.capturedPhraseCount = self.transcript.count
                    let label = segment.speakerHint == .presenter ? "You" : "Reviewer"
                    self.recentTranscript.append("\(label): \(phrase)")
                    if self.recentTranscript.count > 12 {
                        self.recentTranscript.removeFirst(self.recentTranscript.count - 12)
                    }
                }
            } catch is CancellationError {
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func runLiveExtraction() async {
        guard modelAvailable, let note = currentNote, let context = modelContext else { return }
        let fresh = transcript.peekNewSegments()
        guard !fresh.isEmpty else { return }
        let chunk = fresh
            .map { "[\($0.speakerHint.rawValue)] \($0.text)" }
            .joined(separator: "\n")
        isExtracting = true
        defer { isExtracting = false }
        do {
            try await liveExtractor.extractAndCheckpoint(chunk: chunk, into: note, context: context)
            transcript.commitExtracted(count: fresh.count)
            lastExtractionFailed = false
            livePoints = note.sortedActionItems.map(\.oneLiner)
                + note.sortedDecisions.map { "✓ \($0.statement)" }
                + note.sortedOpenQuestions.map { "? \($0.text)" }
        } catch {
            lastExtractionFailed = true
            errorMessage = error.localizedDescription
        }
    }

    static func defaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Review — \(formatter.string(from: .now))"
    }
}
