import Foundation
import Speech
import AVFoundation

/// Real on-device transcription using `SpeechAnalyzer` + `SpeechTranscriber`,
/// fed by the microphone via `CaptureInputSequenceProvider`.
///
/// Kept on the main actor (the project default) so all audio/session state
/// lives on a single actor, avoiding Sendable-crossing with the analyzer and
/// capture session. Only *finalized* phrases are emitted; volatile partials
/// from the `progressiveTranscription` preset are filtered out.
@MainActor
final class SpeechTranscriptionService: TranscriptionProviding {
    enum TranscriptionError: Error {
        case unsupportedLocale
        case micPermissionDenied
        case noMicrophone
    }

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var provider: CaptureInputSequenceProvider?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?

    func start() async throws -> AsyncThrowingStream<String, Error> {
        // 1. Microphone permission.
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw TranscriptionError.micPermissionDenied
        }

        // 2. Resolve a supported locale and build the transcriber module.
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            throw TranscriptionError.unsupportedLocale
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        self.transcriber = transcriber

        // 3. Ensure the on-device transcription assets are installed.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        // 4. Wire the default microphone into an analyzer input sequence.
        guard let device = AVCaptureDevice.default(.microphone, for: .audio, position: .unspecified) else {
            throw TranscriptionError.noMicrophone
        }
        let provider = try await CaptureInputSequenceProvider.providerWithSession(
            from: device,
            compatibleWith: [transcriber]
        )
        self.provider = provider

        // 5. Create the analyzer and begin capturing.
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        provider.captureSession.startRunning()

        let inputs = provider.analyzerInputs
        analysisTask = Task { [analyzer] in
            _ = try? await analyzer.analyzeSequence(inputs)
        }

        // 6. Bridge finalized results into the returned stream.
        return AsyncThrowingStream { continuation in
            resultsTask = Task { [transcriber] in
                do {
                    for try await result in transcriber.results where result.isFinal {
                        let phrase = String(result.text.characters)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !phrase.isEmpty {
                            continuation.yield(phrase)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.resultsTask?.cancel() }
            }
        }
    }

    func stop() async {
        analysisTask?.cancel()
        resultsTask?.cancel()
        provider?.captureSession.stopRunning()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        transcriber = nil
        provider = nil
        analysisTask = nil
        resultsTask = nil
    }
}
