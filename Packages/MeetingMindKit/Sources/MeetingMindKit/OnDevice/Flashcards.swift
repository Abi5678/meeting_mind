import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A deck of question-and-answer cards made from a note. Decks aren't saved, same as quizzes.
public struct FlashcardDeck: Codable, Equatable, Sendable {
    public struct Card: Codable, Equatable, Hashable, Sendable {
        public var front: String
        public var back: String

        public init(front: String, back: String) {
            self.front = front
            self.back = back
        }
    }

    public var title: String
    public var cards: [Card]

    public init(title: String, cards: [Card]) {
        self.title = title
        self.cards = cards
    }
}

/// Flashcards: the prompt and the checks around the on-device model, apart from it so they can be
/// tested anywhere.
public enum NoteFlashcards {
    static let maxCards = 12

    static let instructions = """
        You write flashcards that help someone learn their own notes. Each card has a short \
        question or term on the front and its answer on the back. Every card must come from the \
        notes; never add outside knowledge. Keep fronts under 15 words and backs under 25. Each \
        card covers a different fact: never ask the same thing twice in other words, and never \
        write cards about the notes or the deck themselves, such as who is mentioned or how many \
        cards there are.
        """

    static func prompt(notes: String) -> String {
        """
        Write one flashcard for each distinct fact, name, date, number or definition in these \
        notes, up to \(maxCards). Stop when the facts run out: a short note makes a short deck. \
        Give the deck a short title about the notes' topic.

        NOTES:
        \(notes.prefix(words: NoteQuiz.maxNoteWords))
        """
    }

    /// Trims the cards and drops blank ones and repeated fronts, keeping at most `maxCards`. None
    /// left means the note has nothing to learn, and asking again with the same notes won't help.
    static func normalized(_ deck: FlashcardDeck) throws -> FlashcardDeck {
        var seen: Set<String> = []
        let cards = deck.cards
            .map { FlashcardDeck.Card(front: $0.front.trimmingCharacters(in: .whitespacesAndNewlines),
                                      back: $0.back.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.front.isEmpty && !$0.back.isEmpty && seen.insert($0.front.lowercased()).inserted }
            .prefix(maxCards)
        guard !cards.isEmpty else { throw OnDeviceAIError.notEnoughContent }
        return FlashcardDeck(title: deck.title.trimmingCharacters(in: .whitespacesAndNewlines), cards: Array(cards))
    }
}

#if canImport(FoundationModels)
/// Writes flashcards from a note with Apple's on-device model.
@available(iOS 26, macOS 26, *)
public struct OnDeviceFlashcardWriter: Sendable {
    public init() {}

    public func deck(fromNotes notes: String) async throws -> FlashcardDeck {
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { throw OnDeviceAIError.emptyNotes }

        let session = LanguageModelSession(instructions: NoteFlashcards.instructions)
        let generated = try await session.respond(to: NoteFlashcards.prompt(notes: notes), generating: GeneratedDeck.self).content
        let cards = generated.cards.map { FlashcardDeck.Card(front: $0.front, back: $0.back) }
        return try NoteFlashcards.normalized(FlashcardDeck(title: generated.title, cards: cards))
    }

    @Generable
    struct GeneratedDeck {
        @Guide(description: "A short deck title, at most 6 words")
        var title: String
        @Guide(description: "Cards covering different facts from the notes", .count(1...12))
        var cards: [GeneratedCard]
    }

    @Generable
    struct GeneratedCard {
        @Guide(description: "A question or term, at most 15 words")
        var front: String
        @Guide(description: "The answer from the notes, at most 25 words")
        var back: String
    }
}
#endif
