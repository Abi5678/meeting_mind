import Foundation
import Testing

@testable import MeetingMindKit

@Suite("Note search")
struct NoteSearchTests {
    static let trip = UUID()
    static let launch = UUID()
    static let shopping = UUID()
    static let photo = UUID()
    static let paragraph = Block(type: .paragraph, runs: [.plain("Passport, rain jacket, book trams. Remember the adapter.")])

    static let passages: [SearchPassage] =
        SearchPassage.passages(noteID: trip, title: "Trip plan", blocks: [paragraph])
        + SearchPassage.passages(
            noteID: launch, title: "Launch sync", blocks: [Block(type: .image(id: photo), runs: [])],
            photoText: [photo: "Q3 roadmap\nonboarding revamp\npricing page"],
            transcript: [
                TranscriptPiece(start: 0, end: 4, text: "Morning everyone."),
                TranscriptPiece(start: 62, end: 70, text: "We agreed to move the launch date to March 14."),
            ],
            wordsPerPassage: 2)
        + SearchPassage.passages(noteID: shopping, title: "Saturday", blocks: [
            Block(type: .bulletedList, runs: [.plain("Buy milk, eggs and bananas at the grocery store")]),
        ])

    static let index = SearchIndex(passages: passages)

    @Test("A word finds its block, and the snippet marks it")
    func findsBlock() throws {
        let hit = try #require(Self.index.search("adapter").first)
        #expect(hit.passage.noteID == Self.trip)
        #expect(hit.passage.source == .block(Self.paragraph.id))
        #expect(hit.matches.map { String(hit.snippet[$0]) } == ["adapter"])
    }

    @Test("A transcript hit carries the time it was said")
    func transcriptTime() throws {
        let hit = try #require(Self.index.search("launch date").first { $0.passage.source != .title })
        #expect(hit.passage.source == .transcript(start: 62))
    }

    @Test("A hit in a long stretch of transcript seeks to the piece that said it")
    func transcriptPieceTime() throws {
        let passages = SearchPassage.passages(noteID: Self.launch, title: "", blocks: [], transcript: [
            TranscriptPiece(start: 0, end: 4, text: "Okay, let's start the budget review."),
            TranscriptPiece(start: 4, end: 8, text: "Next quarter is forty thousand dollars."),
            TranscriptPiece(start: 8, end: 12, text: "Sam will book the venue."),
        ])
        #expect(passages.count == 1)
        let index = SearchIndex(passages: passages)
        #expect(index.search("forty thousand").first?.passage.source == .transcript(start: 4))
        #expect(index.search("venue").first?.passage.source == .transcript(start: 8))
        #expect(index.search("budget").first?.passage.source == .transcript(start: 0))
    }

    @Test("Text in a photo is found")
    func photoText() throws {
        let hit = try #require(Self.index.search("pricing").first)
        #expect(hit.passage.source == .photo(Self.photo))
    }

    @Test("Plurals, capitals and accents don't get in the way")
    func folding() {
        #expect(Self.index.search("PASSPORTS").first?.passage.noteID == Self.trip)
        #expect(Self.index.search("bánana").first?.passage.noteID == Self.shopping)
    }

    @Test("The last word matches as a prefix while typing, but not once finished")
    func prefix() {
        #expect(Self.index.search("roadm").first?.passage.source == .photo(Self.photo))
        #expect(Self.index.search("roadm ").isEmpty)
    }

    @Test("Related words find what the query doesn't say")
    func expansion() {
        #expect(Self.index.search("supermarket").isEmpty)
        let hits = Self.index.search("supermarket") { $0 == "supermarket" ? [("grocery", 0.4)] : [] }
        #expect(hits.first?.passage.noteID == Self.shopping)
    }

    @Test("A passage with every word beats one with a single repeated word")
    func coverage() {
        let a = UUID(), b = UUID()
        let index = SearchIndex(passages: [
            SearchPassage(noteID: a, source: .title, text: "budget budget budget budget"),
            SearchPassage(noteID: b, source: .title, text: "travel budget for March"),
        ])
        #expect(index.search("travel budget").first?.passage.noteID == b)
    }

    @Test("Stop words in a longer query are ignored")
    func stopWords() {
        #expect(Self.index.search("where is the adapter").first?.passage.noteID == Self.trip)
    }

    @Test("A timed transcript replaces the untimed copy in its block")
    func transcriptDedup() {
        let text = "Morning everyone. We agreed to move the launch date."
        let passages = SearchPassage.passages(
            noteID: Self.launch, title: "", blocks: [Block(type: .paragraph, runs: [.plain(text)])],
            transcript: [TranscriptPiece(start: 0, end: 5, text: text)], transcriptBlockText: text)
        #expect(passages.map(\.source) == [.transcript(start: 0)])
    }

    @Test("Long passages are cut to a snippet around the match")
    func snippet() throws {
        let words = (1...200).map { "word\($0)" }.joined(separator: " ")
        let index = SearchIndex(passages: [SearchPassage(noteID: UUID(), source: .title, text: words + " needle " + words)])
        let hit = try #require(index.search("needle").first)
        #expect(hit.snippet.hasPrefix("…") && hit.snippet.hasSuffix("…"))
        #expect(hit.snippet.count < 200)
        #expect(hit.matches.map { String(hit.snippet[$0]) } == ["needle"])
    }

    @Test("One note gives at most perNote hits")
    func perNoteCap() {
        let id = UUID()
        let index = SearchIndex(passages: (0..<10).map { SearchPassage(noteID: id, source: .transcript(start: Double($0)), text: "alpha \($0)") })
        #expect(index.search("alpha", perNote: 3).count == 3)
    }
}

@Suite("Transcript chunker")
struct TranscriptChunkerTests {
    @Test("Short text is one chunk")
    func short() {
        #expect(TranscriptChunker.chunks("Hello there. How are you?", maxWords: 50) == ["Hello there. How are you?"])
    }

    @Test("Chunks end at sentence ends and stay under the limit")
    func sentences() {
        let sentence = "One two three four five."
        let chunks = TranscriptChunker.chunks(Array(repeating: sentence, count: 10).joined(separator: " "), maxWords: 12)
        #expect(chunks.count == 5)
        #expect(chunks.allSatisfy { $0.hasSuffix(".") && $0.split(separator: " ").count <= 12 })
    }

    @Test("Unpunctuated speech is split by words")
    func unpunctuated() {
        let text = (1...25).map { "w\($0)" }.joined(separator: " ")
        let chunks = TranscriptChunker.chunks(text, maxWords: 10)
        #expect(chunks.map { $0.split(separator: " ").count } == [10, 10, 5])
    }
}
