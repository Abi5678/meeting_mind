//
//  MusicCheck.swift
//  MeetingMindKit
//
// Spots an imported song before it's summarized as if it were a meeting. Audio is checked with
// Apple's built-in sound classifier; a YouTube video, which has no audio here, by its captions.

import Foundation
import AVFoundation
import SoundAnalysis

public enum MusicCheck {
    /// Whether a file sounds more like music or singing than people talking. Listens to a few short
    /// clips spread through the file, so an hour-long recording takes about as long as a short one.
    public static func soundsLikeMusic(fileAt url: URL, clips: Int = 8, clipLength: TimeInterval = 6) throws -> Bool {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let clipFrames = AVAudioFramePosition(clipLength * format.sampleRate)
        let starts: [AVAudioFramePosition] = file.length <= clipFrames * AVAudioFramePosition(clips)
            ? [0]
            : (0..<clips).map { AVAudioFramePosition($0) * (file.length - clipFrames) / AVAudioFramePosition(clips - 1) }
        let framesEach = starts.count == 1 ? file.length : clipFrames

        let analyzer = SNAudioStreamAnalyzer(format: format)
        let listener = Listener()
        try analyzer.add(SNClassifySoundRequest(classifierIdentifier: .version1), withObserver: listener)
        // The clips are fed back to back, as if they were one short recording.
        var position: AVAudioFramePosition = 0
        for start in starts {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(framesEach)) else { break }
            file.framePosition = start
            try file.read(into: buffer, frameCount: AVAudioFrameCount(framesEach))
            analyzer.analyze(buffer, atAudioFramePosition: position)
            position += AVAudioFramePosition(buffer.frameLength)
        }
        analyzer.completeAnalysis() // Returns once every result has been delivered.

        // Stretches that are neither (silence, a door) don't count either way.
        let heard = listener.windows.filter { max($0.speech, $0.music) >= 0.3 }
        guard !heard.isEmpty else { return false }
        return Double(heard.filter { $0.music > $0.speech }.count) / Double(heard.count) >= 0.6
    }

    /// Whether captions read like song lyrics: mostly marked as music (♪, [Music]), or a chorus
    /// repeating. Talks measured at 2–4% repeated four-word phrases; songs at 40–80%.
    public static func captionsLookLikeSong(_ pieces: [TranscriptPiece]) -> Bool {
        let lines = pieces.map(\.text).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }
        let marked = lines.filter { $0.contains("♪") || $0.localizedCaseInsensitiveContains("[music]") }
        if Double(marked.count) / Double(lines.count) >= 0.5 { return true }

        let words = lines.joined(separator: " ").lowercased()
            .split { !$0.isLetter && $0 != "'" }.map(String.init)
        guard words.count >= 50 else { return false }
        let phrases = (0...(words.count - 4)).map { words[$0..<$0 + 4].joined(separator: " ") }
        let counts = Dictionary(phrases.map { ($0, 1) }, uniquingKeysWith: +)
        return Double(phrases.filter { counts[$0, default: 0] > 1 }.count) / Double(phrases.count) >= 0.3
    }

    /// Collects speech and music confidence for each window the classifier hears.
    private final class Listener: NSObject, SNResultsObserving {
        var windows: [(speech: Double, music: Double)] = []

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let result = result as? SNClassificationResult else { return }
            func confidence(_ label: String) -> Double { result.classification(forIdentifier: label)?.confidence ?? 0 }
            windows.append((confidence("speech"), max(confidence("music"), confidence("singing"))))
        }
    }
}
