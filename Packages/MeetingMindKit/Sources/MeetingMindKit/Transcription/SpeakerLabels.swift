import Foundation
import FluidAudio

/// One word of a transcript and when it was said.
public struct TimedWord: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// A stretch of a recording held by one voice. `speaker` is the diarizer's own id for it.
public struct SpeakerTurn: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var speaker: String

    public init(start: TimeInterval, end: TimeInterval, speaker: String) {
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}

public enum SpeakerLabels {
    /// The transcript as one piece per stretch of speech by one voice, each starting
    /// "Speaker 1: ", with voices numbered in the order they first speak. Nil when fewer than two
    /// voices speak, since labelling a single speaker adds nothing.
    public static func pieces(words: [TimedWord], turns: [SpeakerTurn]) -> [TranscriptPiece]? {
        var labels = words.map { speaker(from: $0.start, to: $0.end, in: turns) }
        // A word between turns stays with the voice before it (or, at the start, the one after).
        for i in labels.indices.dropFirst() where labels[i] == nil { labels[i] = labels[i - 1] }
        for i in labels.indices.reversed().dropFirst() where labels[i] == nil { labels[i] = labels[i + 1] }
        guard Set(labels.compactMap { $0 }).count > 1 else { return nil }
        // The diarizer hears a new voice up to a second late, so a reply's first word can end the
        // turn before it: "…is not ready. Fine" / "by me." A short word after a sentence's end,
        // just before the voice changes, moves to the new voice. (Moving more words than one, or
        // longer ones, cost accuracy on real meetings.)
        for i in words.indices.dropFirst().dropLast()
        where labels[i] != labels[i + 1] && labels[i - 1] == labels[i] && ends(words[i - 1]) && !ends(words[i])
            && words[i].end - words[i].start <= 1 {
            labels[i] = labels[i + 1]
        }

        var names: [String: String] = [:]
        var pieces: [TranscriptPiece] = []
        var current: String?
        for (word, label) in zip(words, labels) {
            guard let label else { continue }
            if names[label] == nil { names[label] = "Speaker \(names.count + 1)" }
            if label == current, let last = pieces.indices.last {
                pieces[last].text += " " + word.text
                pieces[last].end = word.end
            } else {
                pieces.append(TranscriptPiece(start: word.start, end: word.end, text: "\(names[label]!): \(word.text)"))
                current = label
            }
        }
        return pieces
    }

    private static func ends(_ word: TimedWord) -> Bool { word.text.last.map { ".?!".contains($0) } ?? false }

    /// The voice covering most of the span, else the nearest one within a second.
    static func speaker(from start: TimeInterval, to end: TimeInterval, in turns: [SpeakerTurn]) -> String? {
        func overlap(_ turn: SpeakerTurn) -> TimeInterval { max(0, min(end, turn.end) - max(start, turn.start)) }
        if let best = turns.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 { return best.speaker }
        let middle = (start + end) / 2
        func distance(_ turn: SpeakerTurn) -> TimeInterval { min(abs(turn.start - middle), abs(turn.end - middle)) }
        guard let nearest = turns.min(by: { distance($0) < distance($1) }), distance(nearest) < 1 else { return nil }
        return nearest.speaker
    }
}

/// Finds who spoke when in a recording, on the device, with pyannote's segmentation and speaker
/// models and VBx clustering (through FluidAudio). The models, about 21 MB, download on first use.
public struct SpeakerDiarizer: Sendable {
    public init() {}

    /// Downloads the models if the device lacks them. Start it when recording starts.
    public func prepare() async throws {
        try await OfflineDiarizerManager().prepareModels()
    }

    /// Waits up to `limit` for the models, downloading them if the device lacks them. False when
    /// they aren't ready in time or can't be had; the download carries on past the limit, for next
    /// time.
    public func modelsReady(within limit: Duration) async -> Bool {
        await finishes(within: limit) { try await prepare() }
    }

    public func turns(fileAt url: URL) async throws -> [SpeakerTurn] {
        let manager = OfflineDiarizerManager()
        try await manager.prepareModels()
        return try await manager.process(url).segments.map {
            SpeakerTurn(start: TimeInterval($0.startTimeSeconds), end: TimeInterval($0.endTimeSeconds), speaker: $0.speakerId)
        }
    }
}
