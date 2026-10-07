#if canImport(Speech)
import AVFoundation
import Foundation
import Speech

/// Transcribes a recording with Apple's newer speech model (SpeechAnalyzer), which runs entirely on
/// the device, handles long audio in one pass, and times every phrase so a note can seek to it.
/// `SpeechFileTranscriber` remains the fallback on older systems.
@available(iOS 26, macOS 26, *)
public struct OnDeviceTranscriber: Sendable {
    public enum Failure: Error, LocalizedError, Equatable {
        case unsupportedLocale
        public var errorDescription: String? { "On-device transcription doesn't support this language yet." }
    }

    public let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    public static var isAvailable: Bool { SpeechTranscriber.isAvailable }

    /// Downloads the speech model for `locale` if the device lacks it. Start it when recording
    /// starts, so the model is ready by the time the recording ends.
    public func prepare() async throws {
        _ = try await transcriber()
    }

    /// Waits up to `limit` for the speech model, downloading it if the device lacks it, and reports
    /// how much of the download is done, 0...1. False when it isn't ready in time or can't be had.
    /// The system may hold a download back (on cellular, say) for as long as it likes, so this is
    /// what transcribing should wait on, not `prepare()`; the download carries on past the limit.
    public func modelReady(
        within limit: Duration,
        downloadProgress: @Sendable @escaping (Double) async -> Void = { _ in }
    ) async -> Bool {
        let request: AssetInstallationRequest?
        do {
            request = try await AssetInventory.assetInstallationRequest(supporting: [makeTranscriber()])
        } catch {
            return false
        }
        guard let request else { return true }
        let progress = Task {
            while !Task.isCancelled {
                await downloadProgress(request.progress.fractionCompleted)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        let ready = await finishes(within: limit) { try await request.downloadAndInstall() }
        progress.cancel()
        // So no late report lands after the caller has moved on.
        await progress.value
        return ready
    }

    /// - Parameter progress: the fraction of the recording transcribed so far, 0...1. First reported,
    ///   as 0, once the model has started, which takes some 20 seconds whatever the recording's length.
    public func transcribe(
        fileAt url: URL,
        progress: @Sendable @escaping (Double) async -> Void = { _ in }
    ) async throws -> [TranscriptPiece] {
        try await transcription(fileAt: url, progress: progress).pieces
    }

    /// The phrases, as `transcribe` gives them, and every word with its time, for telling speakers
    /// apart.
    public func transcription(
        fileAt url: URL,
        progress: @Sendable @escaping (Double) async -> Void = { _ in }
    ) async throws -> (pieces: [TranscriptPiece], words: [TimedWord]) {
        let transcriber = try await transcriber()
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate

        let collector = Task {
            var pieces: [TranscriptPiece] = []
            var words: [TimedWord] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let piece = TranscriptPiece(start: result.range.start.seconds, end: result.range.end.seconds, text: text)
                pieces.append(piece)
                for run in result.text.runs {
                    guard let range = run.audioTimeRange else { continue }
                    let word = String(result.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !word.isEmpty { words.append(TimedWord(start: range.start.seconds, end: range.end.seconds, text: word)) }
                }
                if duration > 0 { await progress(min(1, piece.end / duration)) }
            }
            return (pieces, words)
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            // Starting the model is the long wait before the first phrase. Done first, that wait can be
            // shown as starting rather than as transcribing stuck at 0%.
            try await analyzer.prepareToAnalyze(in: file.processingFormat)
            await progress(0)
            if let end = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            throw error
        }
        let (pieces, words) = try await collector.value
        return (pieces.sorted { $0.start < $1.start }, words.sorted { $0.start < $1.start })
    }

    private func transcriber() async throws -> SpeechTranscriber {
        let transcriber = try await makeTranscriber()
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        return transcriber
    }

    private func makeTranscriber() async throws -> SpeechTranscriber {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw Failure.unsupportedLocale
        }
        // The plain transcription preset, with each word's time added.
        let preset = SpeechTranscriber.Preset.transcription
        return SpeechTranscriber(
            locale: supported, transcriptionOptions: preset.transcriptionOptions, reportingOptions: preset.reportingOptions,
            attributeOptions: preset.attributeOptions.union([.audioTimeRange]))
    }
}
#endif
