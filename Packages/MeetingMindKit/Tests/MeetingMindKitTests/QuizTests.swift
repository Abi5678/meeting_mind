import Foundation
import Testing

@testable import MeetingMindKit

@Suite("Quiz generation")
struct QuizTests {
    private static let quiz = Quiz(
        title: "Cabin Trip Check",
        questions: [
            .init(prompt: "What needs booking?", options: ["Cabin", "Flight", "Car", "Boat"], answerIndex: 0,
                  explanation: "The notes say to book the cabin."),
            .init(prompt: "What snack is packed?", options: ["Chips", "Trail mix", "Fruit", "Nothing"], answerIndex: 1,
                  explanation: "Trail mix is on the packing list."),
        ]
    )

    @Test("The correct answer lands among the options, and answerIndex points at it")
    func shufflesCorrectAnswer() {
        var random = SystemRandomNumberGenerator()
        var positions = Set<Int>()
        for _ in 0..<50 {
            let question = NoteQuiz.question(prompt: "What needs booking?", correct: "Cabin",
                                             wrong: ["Flight", "Car", "Boat"], explanation: "", using: &random)
            #expect(question.options.count == 4)
            #expect(question.options[question.answerIndex] == "Cabin")
            #expect(Set(question.options) == ["Cabin", "Flight", "Car", "Boat"])
            positions.insert(question.answerIndex)
        }
        #expect(positions.count > 1)
    }

    @Test("A wrong answer that repeats the right one, or another wrong one, is dropped")
    func dropsDuplicateOptions() {
        var random = SystemRandomNumberGenerator()
        let question = NoteQuiz.question(prompt: "Q", correct: "Cabin", wrong: ["cabin", "Car", "Car", ""],
                                         explanation: "", using: &random)
        #expect(question.options.sorted() == ["Cabin", "Car"])
        #expect(question.options[question.answerIndex] == "Cabin")
    }

    @Test("Questions without a real choice are dropped")
    func dropsUngradeableQuestions() throws {
        var broken = Self.quiz
        broken.questions.append(.init(prompt: "Bad", options: ["A", "B"], answerIndex: 7, explanation: ""))
        broken.questions.append(.init(prompt: "Single", options: ["A"], answerIndex: 0, explanation: ""))
        #expect(try NoteQuiz.playable(broken).questions == Self.quiz.questions)
    }

    @Test("A quiz with no gradeable questions is .notEnoughContent")
    func noPlayableQuestions() {
        #expect(throws: OnDeviceAIError.notEnoughContent) {
            try NoteQuiz.playable(Quiz(title: "Nothing", questions: []))
        }
    }

    @Test("The prompt carries the notes, cut to fit the on-device model")
    func prompt() {
        #expect(NoteQuiz.prompt(notes: "Book cabin. Pack trail mix.").hasSuffix("NOTES:\nBook cabin. Pack trail mix."))
        let long = Array(repeating: "word", count: 5_000).joined(separator: " ")
        let words = NoteQuiz.prompt(notes: long).split(whereSeparator: \.isWhitespace).filter { $0 == "word" }
        #expect(words.count == NoteQuiz.maxNoteWords)
    }
}
