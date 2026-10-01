import Foundation

/// What was recorded, which decides how it is written up: a meeting gets decisions, action items
/// and a recap email; a talk gets its key points and takeaways; a memo (a recipe, directions, a
/// workout) gets headings chosen to suit it; a song is kept as its lyrics.
public enum RecordingKind: String, Codable, CaseIterable, Sendable {
    case meeting
    case talk
    case memo
    case song
}
