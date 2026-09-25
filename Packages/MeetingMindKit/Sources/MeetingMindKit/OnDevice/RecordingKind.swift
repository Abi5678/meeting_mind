import Foundation

/// What was recorded, which decides how it is written up: a meeting gets decisions, action items
/// and a recap email; a talk gets its key points and takeaways; a song is kept as its lyrics.
public enum RecordingKind: String, Codable, CaseIterable, Sendable {
    case meeting
    case talk
    case song
}
