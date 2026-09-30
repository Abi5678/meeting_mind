import Testing

@testable import MeetingMindKit

@Suite("SpeakerLabels")
struct SpeakerLabelsTests {
    private static func words(_ text: String, from start: Double) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { i, word in
            TimedWord(start: start + Double(i) * 0.5, end: start + Double(i) * 0.5 + 0.4, text: String(word))
        }
    }

    @Test("Each stretch by one voice becomes a labelled piece, voices numbered as they first speak")
    func labelsTurns() throws {
        let words = Self.words("shall we start", from: 0) + Self.words("yes let's go", from: 3) + Self.words("great", from: 6)
        let turns = [
            SpeakerTurn(start: 0, end: 2, speaker: "S7"),
            SpeakerTurn(start: 2.8, end: 5, speaker: "S2"),
            SpeakerTurn(start: 5.8, end: 7, speaker: "S7"),
        ]

        let pieces = try #require(SpeakerLabels.pieces(words: words, turns: turns))

        #expect(pieces.map(\.text) == ["Speaker 1: shall we start", "Speaker 2: yes let's go", "Speaker 1: great"])
        #expect(pieces[1].start == 3)
        #expect(pieces[1].end == 4.4)
    }

    @Test("A word between turns goes to the nearest voice within a second, else stays with the one before")
    func wordsBetweenTurns() throws {
        let words = [
            TimedWord(start: 0, end: 0.4, text: "hi"),
            TimedWord(start: 1.2, end: 1.4, text: "there"),  // 0.3 s after A's turn ends
            TimedWord(start: 10, end: 10.4, text: "anyway"),  // far from every turn
            TimedWord(start: 20, end: 20.4, text: "hello"),
        ]
        let turns = [SpeakerTurn(start: 0, end: 1, speaker: "A"), SpeakerTurn(start: 19.9, end: 21, speaker: "B")]

        let pieces = try #require(SpeakerLabels.pieces(words: words, turns: turns))

        #expect(pieces.map(\.text) == ["Speaker 1: hi there anyway", "Speaker 2: hello"])
    }

    @Test("A reply's first word, heard late, moves from the end of the turn before to the reply")
    func lateReply() throws {
        let words = Self.words("it is not ready. Fine", from: 0) + Self.words("by me.", from: 2.5)
        let turns = [SpeakerTurn(start: 0, end: 2.4, speaker: "A"), SpeakerTurn(start: 2.4, end: 4, speaker: "B")]

        let pieces = try #require(SpeakerLabels.pieces(words: words, turns: turns))

        #expect(pieces.map(\.text) == ["Speaker 1: it is not ready.", "Speaker 2: Fine by me."])
    }

    @Test("One voice, or none found, leaves the transcript unlabelled")
    func singleSpeaker() {
        let words = Self.words("just me talking here", from: 0)
        #expect(SpeakerLabels.pieces(words: words, turns: [SpeakerTurn(start: 0, end: 3, speaker: "A")]) == nil)
        #expect(SpeakerLabels.pieces(words: words, turns: []) == nil)
        #expect(SpeakerLabels.pieces(words: [], turns: []) == nil)
    }
}
