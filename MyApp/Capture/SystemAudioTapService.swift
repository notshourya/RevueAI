import Foundation
import Speech
import AVFoundation
import CoreAudio

/// Captures other participants' audio (Zoom/Meet/Teams — any app) via a Core
/// Audio process tap, transcribes it on-device, and emits finalized phrases.
///
/// This runs a *global* tap (all processes' output, mixed to stereo), routed
/// through a private aggregate device whose IO block feeds a dedicated
/// `SpeechAnalyzer`. It is intentionally failure-tolerant: if the tap can't be
/// created (missing entitlement, denied permission, unsupported OS), `start()`
/// throws and the coordinator simply continues mic-only.
///
/// Not main-actor isolated: the Core Audio IO block runs on a realtime thread,
/// so buffer conversion happens off-main and results are bridged back through a
/// `Sendable` async stream.
final class SystemAudioTapService: TranscriptionProviding, @unchecked Sendable {
    enum TapError: LocalizedError {
        case missingUsageDescription
        case unsupportedLocale
        case tapCreationFailed(OSStatus)
        case aggregateCreationFailed(OSStatus)
        case formatUnavailable
        case ioProcFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .missingUsageDescription:
                return "System-audio capture isn’t configured (add “NSAudioCaptureUsageDescription” and the "
                    + "Audio Input capability). Continuing with microphone only."
            case .unsupportedLocale:
                return "On-device transcription isn’t available for the current language."
            case .tapCreationFailed(let s):
                return "Couldn’t create the system-audio tap (status \(s)). Continuing with microphone only."
            case .aggregateCreationFailed(let s):
                return "Couldn’t create the capture device (status \(s)). Continuing with microphone only."
            case .formatUnavailable:
                return "The system-audio stream format was unavailable."
            case .ioProcFailed(let s):
                return "Couldn’t start reading system audio (status \(s))."
            }
        }
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?

    func start() async throws -> AsyncThrowingStream<String, Error> {
        guard Bundle.main.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") != nil else {
            throw TapError.missingUsageDescription
        }

        // Transcriber + assets.
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            throw TapError.unsupportedLocale
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        self.transcriber = transcriber
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        // 1. Create a global process tap (exclude nothing → capture everything).
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var newTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTap)
        guard tapStatus == noErr, newTap != kAudioObjectUnknown else {
            throw TapError.tapCreationFailed(tapStatus)
        }
        tapID = newTap

        // 2. Tap UID + stream format.
        let tapUID = try Self.property(tapID, kAudioTapPropertyUID, CFString.self)
        var asbd = try Self.property(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription.self)
        guard let tapFormat = AVAudioFormat(streamDescription: &asbd) else {
            throw TapError.formatUnavailable
        }

        // 3. Private aggregate device containing the tap.
        let aggregateDict: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "RevueAI System Capture",
            kAudioAggregateDeviceUIDKey as String: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [kAudioSubTapUIDKey as String: tapUID],
            ],
        ]
        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDict as CFDictionary, &newAggregate)
        guard aggregateStatus == noErr, newAggregate != kAudioObjectUnknown else {
            throw TapError.aggregateCreationFailed(aggregateStatus)
        }
        aggregateID = newAggregate

        // 4. Analyzer fed by an async input stream.
        let (inputSequence, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputContinuation = continuation
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        analysisTask = Task { [analyzer] in
            _ = try? await analyzer.analyzeSequence(inputSequence)
        }

        // 5. IO block converts realtime buffers → AnalyzerInput and yields them.
        //    Runs on a realtime audio thread; only touches the Sendable
        //    continuation and locally-captured, immutable values.
        let converter = AnalyzerInputConverter(analyzerFormat: SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]))
        let ioBlock: AudioDeviceIOBlock = { _, inputData, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: tapFormat, bufferListNoCopy: inputData) else { return }
            if let inputs = try? converter.convert(buffer, at: nil) {
                for input in inputs { continuation.yield(input) }
            }
        }
        var procID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, ioBlock)
        guard procStatus == noErr, let procID else {
            throw TapError.ioProcFailed(procStatus)
        }
        ioProcID = procID
        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            throw TapError.ioProcFailed(startStatus)
        }

        // 6. Bridge finalized results into the returned stream.
        return AsyncThrowingStream { streamContinuation in
            let task = Task { [transcriber] in
                do {
                    for try await result in transcriber.results where result.isFinal {
                        let phrase = String(result.text.characters)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !phrase.isEmpty { streamContinuation.yield(phrase) }
                    }
                    streamContinuation.finish()
                } catch {
                    streamContinuation.finish(throwing: error)
                }
            }
            resultsTask = task
            streamContinuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() async {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        inputContinuation?.finish()
        analysisTask?.cancel()
        resultsTask?.cancel()

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        analyzer = nil
        transcriber = nil
        inputContinuation = nil
        analysisTask = nil
        resultsTask = nil
    }

    // MARK: - Property helpers

    /// Reads a single Core Audio object property of a known type.
    private static func property<T>(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector, _ type: T.Type) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.stride)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, value)
        guard status == noErr else { throw TapError.formatUnavailable }
        return value.pointee
    }
}
