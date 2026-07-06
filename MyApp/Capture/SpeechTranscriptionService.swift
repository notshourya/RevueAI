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
    enum TranscriptionError: LocalizedError {
        case missingUsageDescription
        case unsupportedLocale
        case micPermissionDenied
        case noMicrophone

        var errorDescription: String? {
            switch self {
            case .missingUsageDescription:
                return "Microphone access isn’t configured. Add an “NSMicrophoneUsageDescription” "
                    + "string and the App Sandbox “Audio Input” capability to the target, then rebuild."
            case .unsupportedLocale:
                return "On-device transcription isn’t available for the current language."
            case .micPermissionDenied:
                return "Microphone access was denied. Enable it in System Settings › Privacy & Security › Microphone."
            case .noMicrophone:
                return "No microphone was found."
            }
        }
    }

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var provider: CaptureInputSequenceProvider?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?

    func start() async throws -> AsyncThrowingStream<String, Error> {
        // 0. Fail gracefully instead of letting the OS hard-abort the process:
        //    accessing the mic without a usage-description string is fatal.
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            throw TranscriptionError.missingUsageDescription
        }

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
            let task = Task { [transcriber] in
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
            resultsTask = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() async {
        provider?.captureSession.stopRunning()
        analysisTask?.cancel()

        // Flush any remaining finalized results, bounded so we never hang if
        // the input sequence doesn't terminate on its own.
        let finalize = Task { [analyzer] in try? await analyzer?.finalizeAndFinishThroughEndOfInput() }
        try? await Task.sleep(for: .seconds(2))
        finalize.cancel()

        // Let the results consumer drain naturally, then tear down.
        resultsTask?.cancel()
        _ = await resultsTask?.value

        analyzer = nil
        transcriber = nil
        provider = nil
        analysisTask = nil
        resultsTask = nil
    }
}
