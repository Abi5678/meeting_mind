import Foundation

/// A stretch of transcribed speech and when it was said, in seconds from the start of the recording.
public struct TranscriptPiece: Codable, Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    /// The pieces as one transcript, the form summaries and the note's Transcript block use.
    public static func joined(_ pieces: [TranscriptPiece]) -> String {
        pieces.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
