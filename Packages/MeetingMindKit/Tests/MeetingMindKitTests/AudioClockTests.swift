import Foundation
import Testing

@testable import MeetingMindKit

@Suite("Audio clock")
struct AudioClockTests {
    let start = Date(timeIntervalSince1970: 1_000)
    // Recorded 10 s, paused 20 s, recorded 5 more: a 15 s file.
    var spans: [AudioClock.Span] {
        [.init(wallStart: start, fileOffset: 0), .init(wallStart: start + 30, fileOffset: 10)]
    }

    @Test("Moments while recording map to file time, skipping the pause")
    func mapsAcrossPause() {
        #expect(AudioClock.fileTime(at: start + 4, spans: spans, duration: 15) == 4)
        #expect(AudioClock.fileTime(at: start + 10, spans: spans, duration: 15) == 10)
        #expect(AudioClock.fileTime(at: start + 32, spans: spans, duration: 15) == 12)
    }

    @Test("Moments before, during a pause and after the recording have no file time")
    func outsideRecording() {
        #expect(AudioClock.fileTime(at: start - 1, spans: spans, duration: 15) == nil)
        #expect(AudioClock.fileTime(at: start + 20, spans: spans, duration: 15) == nil)
        #expect(AudioClock.fileTime(at: start + 40, spans: spans, duration: 15) == nil)
        #expect(AudioClock.fileTime(at: start, spans: [], duration: 15) == nil)
    }

    @Test("The current block is the latest one marked at or before the playback time")
    func currentBlock() {
        let recording = UUID(), other = UUID()
        let a = Block(type: .paragraph, audioMark: .init(recordingID: recording, time: 2))
        let b = Block(type: .paragraph)
        let c = Block(type: .paragraph, audioMark: .init(recordingID: recording, time: 9))
        let d = Block(type: .paragraph, audioMark: .init(recordingID: other, time: 5))
        let blocks = [a, b, c, d]
        #expect(AudioClock.currentBlock(in: blocks, recordingID: recording, at: 1) == nil)
        #expect(AudioClock.currentBlock(in: blocks, recordingID: recording, at: 5) == a.id)
        #expect(AudioClock.currentBlock(in: blocks, recordingID: recording, at: 30) == c.id)
        #expect(AudioClock.currentBlock(in: blocks, recordingID: other, at: 6) == d.id)
    }

    @Test("A mark round-trips through JSON")
    func markCodable() throws {
        let mark = AudioMark(recordingID: UUID(), time: 12.5)
        let data = try JSONEncoder().encode(mark)
        #expect(try JSONDecoder().decode(AudioMark.self, from: data) == mark)
    }
}
