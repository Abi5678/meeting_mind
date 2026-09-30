#if canImport(Speech)
import AVFoundation
import Foundation
import Speech

/// Turns a recorded meeting file into text with Apple's Speech framework.
///
/// Recognition runs on the device when the locale supports it and the model loads. Otherwise Apple's servers do
/// it, and they stop listening after about a minute, so the file is always fed in windows of
/// at most `windowSeconds`, cut at the quietest nearby moment (see `ChunkPlanner`).
public struct SpeechFileTranscriber: Sendable {
    /// Under the server limit even after `ChunkPlanner` folds a short tail (≤ 5 s) into the last window.
    public static let windowSeconds: TimeInterval = 50

    public enum Failure: Error, LocalizedError, Equatable {
        case notAuthorized
        case unavailable
        /// Some windows failed even on the server; `transcript` holds the ones that came through.
        case incomplete(transcript: String, failedParts: Int, totalParts: Int)

        public var errorDescription: String? {
            switch self {
            case .notAuthorized: "Speech recognition is off for Quolio. Turn it on in Settings."
            case .unavailable: "Speech recognition isn't available for this language right now."
            case let .incomplete(_, failed, total): "\(failed) of \(total) parts of the recording couldn't be transcribed."
            }
        }
    }

    public let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Whether `locale` has a recognizer that can run right now (offline, it may have none).
    public var isAvailable: Bool {
        SFSpeechRecognizer(locale: locale)?.isAvailable ?? false
    }

    public static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    /// - Parameter progress: called before each window with (window, totalWindows), 1-based.
    public func transcribe(
        fileAt url: URL,
        progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async throws -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw Failure.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw Failure.unavailable
        }

        let file = try AVAudioFile(forReading: url)
        let windows = ChunkPlanner.plan(
            totalSamples: Int(file.length),
            sampleRate: Int(file.processingFormat.sampleRate),
            windowSeconds: Self.windowSeconds
        ) { Self.meanSquare(of: file, range: $0) }

        var onDevice = recognizer.supportsOnDeviceRecognition
        var triedServer = false
        return try await Self.transcribeWindows(windows.count, progress: progress) { index in
            do {
                return try await recognize(windows[index], in: file, with: recognizer, onDevice: onDevice)
            } catch where !triedServer && !(error is CancellationError) {
                // The local model can be missing whether or not it was advertised (e.g. the simulator
                // ships none), so the server is tried once even when on-device was never used.
                onDevice = false
                triedServer = true
                return try await recognize(windows[index], in: file, with: recognizer, onDevice: false)
            }
        }
    }

    /// Recognizes each window in turn. A window that fails is skipped so one bad stretch doesn't cost the
    /// rest of the meeting; `Failure.incomplete` then carries the text that did come through. If every
    /// window fails, the first error is thrown as-is since it says more than "0 of N parts".
    static func transcribeWindows(
        _ count: Int,
        progress: @Sendable (Int, Int) async -> Void,
        recognize: (Int) async throws -> String
    ) async throws -> String {
        var texts: [String] = []
        var firstError: Error?
        var failed = 0
        for index in 0..<count {
            try Task.checkCancellation()
            await progress(index + 1, count)
            do {
                let text = try await recognize(index)
                if !text.isEmpty { texts.append(text) }
            } catch let error as CancellationError {
                throw error
            } catch {
                failed += 1
                firstError = firstError ?? error
            }
        }
        if let firstError {
            guard failed < count else { throw firstError }
            throw Failure.incomplete(transcript: texts.joined(separator: " "), failedParts: failed, totalParts: count)
        }
        return texts.joined(separator: " ")
    }

    private func recognize(_ range: ChunkRange, in file: AVAudioFile, with recognizer: SFSpeechRecognizer, onDevice: Bool) async throws -> String {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = onDevice
        request.addsPunctuation = true

        let format = file.processingFormat
        let oneSecond = AVAudioFrameCount(format.sampleRate)
        file.framePosition = AVAudioFramePosition(range.startSample)
        var remaining = range.sampleCount
        while remaining > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: min(oneSecond, AVAudioFrameCount(remaining))) {
            try file.read(into: buffer, frameCount: buffer.frameCapacity)
            guard buffer.frameLength > 0 else { break }
            request.append(buffer)
            remaining -= Int(buffer.frameLength)
        }
        request.endAudio()

        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    once.resume(with: .success(result.bestTranscription.formattedString))
                } else if let error {
                    // "No speech detected": a quiet stretch of the meeting, not a failure.
                    let nsError = error as NSError
                    let noSpeech = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110
                    once.resume(with: noSpeech ? .success("") : .failure(error))
                }
            }
        }
    }

    private static func meanSquare(of file: AVAudioFile, range: Range<Int>) -> Float {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(range.count)) else {
            return .greatestFiniteMagnitude
        }
        file.framePosition = AVAudioFramePosition(range.lowerBound)
        guard (try? file.read(into: buffer, frameCount: buffer.frameCapacity)) != nil,
              buffer.frameLength > 0,
              let samples = buffer.floatChannelData?[0] else {
            return .greatestFiniteMagnitude
        }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        return sum / Float(buffer.frameLength)
    }
}

/// The recognition callback can fire more than once; the continuation must resume exactly once.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<String, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
#endif
