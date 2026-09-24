import Foundation
import Testing

@testable import MeetingMindKit

@Suite("Flashcards")
struct FlashcardTests {
    @Test("Cards are trimmed; blank cards and repeated fronts are dropped")
    func normalizes() throws {
        let deck = FlashcardDeck(title: " Cabin trip ", cards: [
            .init(front: " What needs booking? ", back: "The cabin\n"),
            .init(front: "what needs booking?", back: "A flight"),
            .init(front: "  ", back: "Orphan answer"),
            .init(front: "Snack?", back: ""),
            .init(front: "Snack to pack?", back: "Trail mix"),
        ])
        #expect(try NoteFlashcards.normalized(deck) == FlashcardDeck(title: "Cabin trip", cards: [
            .init(front: "What needs booking?", back: "The cabin"),
            .init(front: "Snack to pack?", back: "Trail mix"),
        ]))
    }

    @Test("A deck is capped at 12 cards")
    func caps() throws {
        let cards = (1...20).map { FlashcardDeck.Card(front: "Q\($0)", back: "A\($0)") }
        let deck = try NoteFlashcards.normalized(FlashcardDeck(title: "Many", cards: cards))
        #expect(deck.cards == Array(cards.prefix(12)))
    }

    @Test("A deck with no usable cards is .notEnoughContent")
    func empty() {
        #expect(throws: OnDeviceAIError.notEnoughContent) {
            try NoteFlashcards.normalized(FlashcardDeck(title: "Nothing", cards: [.init(front: "", back: "x")]))
        }
    }

    @Test("The prompt carries the notes, cut to fit the on-device model")
    func prompt() {
        #expect(NoteFlashcards.prompt(notes: "Book cabin. Pack trail mix.").hasSuffix("NOTES:\nBook cabin. Pack trail mix."))
        let long = Array(repeating: "word", count: 5_000).joined(separator: " ")
        let words = NoteFlashcards.prompt(notes: long).split(whereSeparator: \.isWhitespace).filter { $0 == "word" }
        #expect(words.count == NoteQuiz.maxNoteWords)
    }
}
