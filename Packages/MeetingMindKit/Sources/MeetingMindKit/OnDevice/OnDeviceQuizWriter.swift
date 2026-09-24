import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "Quiz me": the prompt and the checks around the on-device model, apart from it so they can be
/// tested anywhere.
public enum NoteQuiz {
    /// About 1,600 tokens, leaving room in the model's 4,000 for the instructions and five questions.
    static let maxNoteWords = 1_200

    static let instructions = """
        You write multiple-choice quizzes that help someone check what they remember from their \
        own notes. Every question and every correct answer must come from the notes; never test \
        outside knowledge. Wrong answers are plausible but clearly wrong given the notes. Keep \
        answers short. The explanation says in one sentence why the correct answer is right; it is \
        shown after right and wrong answers alike, so never open with praise.
        """

    static func prompt(notes: String) -> String {
        """
        Write up to 5 questions from these notes. If the notes are too short for 5 distinct \
        questions, write fewer rather than repeating yourself or going beyond the notes. Give the \
        quiz a short, playful title about the notes' topic.

        NOTES:
        \(notes.prefix(words: maxNoteWords))
        """
    }

    /// A question with its correct answer shuffled in among the wrong ones. The model is asked for
    /// the right answer separately because small models put it first when choosing an index.
    static func question<R: RandomNumberGenerator>(
        prompt: String, correct: String, wrong: [String], explanation: String, using random: inout R
    ) -> Quiz.Question {
        var seen: Set<String> = [correct.lowercased()]
        var options = wrong.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        let answerIndex = Int.random(in: 0...options.count, using: &random)
        options.insert(correct, at: answerIndex)
        return Quiz.Question(prompt: prompt, options: options, answerIndex: answerIndex, explanation: explanation)
    }

    /// Drops questions that can't be graded. None left means the note has nothing to ask about, and
    /// asking again with the same notes won't change that.
    static func playable(_ quiz: Quiz) throws -> Quiz {
        let questions = quiz.questions.filter(\.isPlayable)
        guard !questions.isEmpty else { throw OnDeviceAIError.notEnoughContent }
        return Quiz(title: quiz.title, questions: questions)
    }
}

#if canImport(FoundationModels)
/// Writes a quiz from a note with Apple's on-device model.
@available(iOS 26, macOS 26, *)
public struct OnDeviceQuizWriter: Sendable {
    public init() {}

    public func quiz(fromNotes notes: String) async throws -> Quiz {
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { throw OnDeviceAIError.emptyNotes }

        let session = LanguageModelSession(instructions: NoteQuiz.instructions)
        let generated = try await session.respond(to: NoteQuiz.prompt(notes: notes), generating: GeneratedQuiz.self).content
        var random = SystemRandomNumberGenerator()
        let questions = generated.questions.map {
            NoteQuiz.question(prompt: $0.question, correct: $0.correctAnswer, wrong: $0.wrongAnswers,
                              explanation: $0.explanation, using: &random)
        }
        return try NoteQuiz.playable(Quiz(title: generated.title, questions: questions))
    }

    @Generable
    struct GeneratedQuiz {
        @Guide(description: "A short, playful quiz title, at most 6 words")
        var title: String
        @Guide(description: "Questions answerable from the notes alone", .count(1...5))
        var questions: [GeneratedQuestion]
    }

    @Generable
    struct GeneratedQuestion {
        var question: String
        @Guide(description: "The correct answer, from the notes, at most 12 words")
        var correctAnswer: String
        @Guide(description: "Plausible but wrong answers, at most 12 words each", .count(3))
        var wrongAnswers: [String]
        @Guide(description: "One sentence on why the correct answer is right")
        var explanation: String
    }
}
#endif
