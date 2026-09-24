import Foundation

/// A moment in a recording: which recording, and how far into its audio file.
public struct AudioMark: Equatable, Sendable, Codable {
    public var recordingID: UUID
    /// Seconds into the audio file.
    public var time: TimeInterval

    public init(recordingID: UUID, time: TimeInterval) {
        self.recordingID = recordingID
        self.time = time
    }
}

/// Maps wall-clock moments (a pen stroke's creation date) to times in a recording's audio file.
///
/// A recording pauses, so the file's timeline isn't the wall clock. Each span notes when the
/// recorder started or resumed and how much audio the file already held at that moment.
public enum AudioClock {
    public struct Span: Equatable, Sendable, Codable {
        public var wallStart: Date
        public var fileOffset: TimeInterval

        public init(wallStart: Date, fileOffset: TimeInterval) {
            self.wallStart = wallStart
            self.fileOffset = fileOffset
        }
    }

    /// The file time at `date`, or nil if the recorder wasn't running then: before it started,
    /// in a pause, or after the recording ended.
    public static func fileTime(at date: Date, spans: [Span], duration: TimeInterval) -> TimeInterval? {
        let spans = spans.sorted { $0.wallStart < $1.wallStart }
        guard let index = spans.lastIndex(where: { $0.wallStart <= date }) else { return nil }
        let span = spans[index]
        let time = span.fileOffset + date.timeIntervalSince(span.wallStart)
        // A span runs until the next one's audio begins; past that the recorder was paused.
        let end = index + 1 < spans.count ? spans[index + 1].fileOffset : duration
        return time <= end ? time : nil
    }

    /// The block to highlight while `recordingID` plays at `time`: the one with the latest mark
    /// at or before it.
    public static func currentBlock(in blocks: [Block], recordingID: UUID, at time: TimeInterval) -> UUID? {
        var best: (id: UUID, time: TimeInterval)?
        for block in blocks {
            guard let mark = block.audioMark, mark.recordingID == recordingID, mark.time <= time else { continue }
            if best == nil || mark.time >= best!.time { best = (block.id, mark.time) }
        }
        return best?.id
    }

    /// A note's transcript runs its recordings end to end, each starting at its offset. The index
    /// of the recording a transcript `time` falls in: the latest start at or before it, the
    /// earliest recording on a tie. Nil when every recording starts later.
    public static func source(at time: TimeInterval, starts: [TimeInterval]) -> Int? {
        var best: Int?
        for (index, start) in starts.enumerated() where start <= time {
            if best.map({ start > starts[$0] }) ?? true { best = index }
        }
        return best
    }
}
