import Foundation

/// A multiple-choice quiz Gemini writes from a note.
///
/// The shape here is mirrored by `GeminiSchema.quiz`, which is sent as the request's
/// `responseSchema`. Keep the two in sync.
public struct Quiz: Codable, Equatable, Sendable {
    public var title: String
    public var questions: [Question]

    public init(title: String, questions: [Question]) {
        self.title = title
        self.questions = questions
    }

    public struct Question: Codable, Equatable, Sendable {
        public var prompt: String
        public var options: [String]
        /// Zero-based index into `options`.
        public var answerIndex: Int
        public var explanation: String

        public init(prompt: String, options: [String], answerIndex: Int, explanation: String) {
            self.prompt = prompt
            self.options = options
            self.answerIndex = answerIndex
            self.explanation = explanation
        }

        /// A question can only be graded if it has a real choice and its answer is one of the options.
        var isPlayable: Bool {
            options.count >= 2 && options.indices.contains(answerIndex)
        }
    }
}
