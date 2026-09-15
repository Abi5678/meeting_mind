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

        public var errorDescription: String? {
            switch self {
            case .notAuthorized: "Speech recognition is off for Instant Notes. Turn it on in Settings."
            case .unavailable: "Speech recognition isn't available for this language right now."
            }
        }
    }

    public let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
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
        var texts: [String] = []
        for (index, window) in windows.enumerated() {
            try Task.checkCancellation()
            await progress(index + 1, windows.count)
            let text: String
            do {
                text = try await recognize(window, in: file, with: recognizer, onDevice: onDevice)
            } catch where onDevice && !(error is CancellationError) {
                // The on-device model can be advertised but not installed (e.g. the simulator); use the server instead.
                onDevice = false
                text = try await recognize(window, in: file, with: recognizer, onDevice: false)
            }
            if !text.isEmpty { texts.append(text) }
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
