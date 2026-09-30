import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A notebook's study guide: the terms to know, questions to test yourself with, and bigger
/// questions to think over, all from its sources.
public struct StudyGuide: Equatable, Sendable {
    public struct Term: Equatable, Sendable {
        public var term: String
        public var meaning: String

        public init(term: String, meaning: String) {
            self.term = term
            self.meaning = meaning
        }
    }

    public struct Question: Equatable, Sendable {
        public var question: String
        public var answer: String

        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }

    public var terms: [Term]
    public var questions: [Question]
    /// Questions with no one answer, asking to explain, compare or weigh up.
    public var discussion: [String]

    public init(terms: [Term], questions: [Question], discussion: [String]) {
        self.terms = terms
        self.questions = questions
        self.discussion = discussion
    }
}

/// Studying a whole notebook: what the model reads for a quiz, flashcards or a study guide, and
/// the study guide's prompt, checks and note.
public enum NotebookStudy {
    /// Each source's title, what the summary took from it, then the start of its own text, cut to
    /// an equal share of the budget. The summary's reading covers all of a long source, its text
    /// gives the details questions are made of, and the share keeps one source from crowding out
    /// the rest. A source with nothing in it is left out. The budget leaves room under
    /// `NoteQuiz.maxNoteWords` for the notebook's title, which quizzes and flashcards put first.
    public static func material(_ sources: [(title: String, digest: SourceDigest?, text: String)], wordBudget: Int = 1_100) -> String {
        let read = sources.compactMap { source -> (title: String, body: String)? in
            let digest = source.digest.map { ([$0.summary] + $0.keyPoints.map { "- \($0)" }).joined(separator: "\n") } ?? ""
            let body = [digest, source.text]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            return body.isEmpty ? nil : (source.title, body)
        }
        let share = max(20, wordBudget / max(1, read.count))
        return read.map { "\($0.title)\n\($0.body.prefix(words: share))" }.joined(separator: "\n\n")
    }

    static let guideInstructions = """
        You write study guides that help someone learn the sources in their notebook: documents, \
        web pages, notes and meeting transcripts. Everything in the guide must come from the \
        sources; never add outside knowledge. Keep it short and plain.
        """

    static func guidePrompt(title: String, material: String) -> String {
        """
        Write a study guide for the notebook "\(title)" from its sources below: the key terms and \
        what each means in the sources, short questions that test the most important facts, with \
        their answers, and open questions to think over. Cover every source, not only the first.

        SOURCES:
        \(material.prefix(words: NoteQuiz.maxNoteWords))
        """
    }

    /// Trims everything and drops blanks and repeats. No terms or questions left means the sources
    /// have nothing to study, and asking again with the same sources won't help.
    static func normalized(_ guide: StudyGuide) throws -> StudyGuide {
        func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var seen: Set<String> = []
        func isNew(_ text: String) -> Bool { !text.isEmpty && seen.insert(text.lowercased()).inserted }

        // "Term:" would read "Term:: its meaning" in the note.
        let terms = guide.terms
            .map { StudyGuide.Term(term: trimmed($0.term).trimmingCharacters(in: CharacterSet(charactersIn: ":")), meaning: trimmed($0.meaning)) }
            .filter { !$0.meaning.isEmpty && isNew($0.term) }
        let questions = guide.questions
            .map { StudyGuide.Question(question: trimmed($0.question), answer: trimmed($0.answer)) }
            .filter { !$0.answer.isEmpty && isNew($0.question) }
        let discussion = guide.discussion.map(trimmed).filter(isNew)
        guard !terms.isEmpty || !questions.isEmpty else { throw OnDeviceAIError.notEnoughContent }
        return StudyGuide(terms: terms, questions: questions, discussion: discussion)
    }

    /// The study guide note: the terms, then the questions with each answer folded away under it
    /// until tapped, then the questions to think over.
    public static func blocks(_ guide: StudyGuide) -> [Block] {
        var blocks: [Block] = []
        func heading(_ text: String) { blocks.append(Block(type: .heading(level: 2), runs: [.plain(text)])) }

        if !guide.terms.isEmpty {
            heading("Key terms")
            blocks += guide.terms.map { Block(type: .bulletedList, runs: [InlineRun(text: $0.term, isBold: true), .plain(": \($0.meaning)")]) }
        }
        if !guide.questions.isEmpty {
            heading("Test yourself")
            for question in guide.questions {
                blocks.append(Block(type: .toggle, runs: [.plain(question.question)], isExpanded: false))
                blocks.append(Block(type: .paragraph, runs: [.plain(question.answer)], indent: 1))
            }
        }
        if !guide.discussion.isEmpty {
            heading("Think it over")
            blocks += guide.discussion.map { Block(type: .numberedList, runs: [.plain($0)]) }
        }
        return blocks
    }
}

#if canImport(FoundationModels)
/// Writes a notebook's study guide with Apple's on-device model.
@available(iOS 26, macOS 26, *)
public struct OnDeviceStudyGuideWriter: Sendable {
    public init() {}

    /// `material` is what `NotebookStudy.material` took from the notebook's sources.
    public func guide(title: String, material: String) async throws -> StudyGuide {
        guard !material.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OnDeviceAIError.emptyNotebook }
        let session = LanguageModelSession(instructions: NotebookStudy.guideInstructions)
        let generated = try await session.respond(to: NotebookStudy.guidePrompt(title: title, material: material),
                                                  generating: GeneratedGuide.self).content
        return try NotebookStudy.normalized(StudyGuide(
            terms: generated.terms.map { StudyGuide.Term(term: $0.term, meaning: $0.meaning) },
            questions: generated.questions.map { StudyGuide.Question(question: $0.question, answer: $0.answer) },
            discussion: generated.discussion
        ))
    }

    @Generable
    struct GeneratedGuide {
        @Guide(description: "Key terms, names and ideas from the sources", .count(1...8))
        var terms: [GeneratedTerm]
        @Guide(description: "Short questions that test the most important facts in the sources", .count(1...6))
        var questions: [GeneratedQuestion]
        @Guide(description: "Open questions to think over, asking to explain, compare or weigh up what the sources say", .count(1...3))
        var discussion: [String]
    }

    @Generable
    struct GeneratedTerm {
        @Guide(description: "The term, name or idea, in a few words")
        var term: String
        @Guide(description: "What it means in the sources, at most 25 words")
        var meaning: String
    }

    @Generable
    struct GeneratedQuestion {
        var question: String
        @Guide(description: "The answer from the sources, at most 25 words")
        var answer: String
    }
}
#endif
