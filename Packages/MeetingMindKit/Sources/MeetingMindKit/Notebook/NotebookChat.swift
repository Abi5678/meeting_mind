import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "Ask this notebook": picks what fits the on-device model from a notebook's sources, numbers it
/// for citing, and builds the prompt.
public enum NotebookChat {
    /// One numbered source handed to the model: a note, with the excerpts of it that matter here.
    public struct Source: Codable, Equatable, Sendable {
        public let number: Int
        public let noteID: UUID
        public let title: String
        public let text: String

        public init(number: Int, noteID: UUID, title: String, text: String) {
            self.number = number
            self.noteID = noteID
            self.title = title
            self.text = text
        }
    }

    /// About 1,350 tokens, leaving room for the instructions, the conversation and the answer.
    static let wordBudget = 1_000
    static let wordsPerExcerpt = 120
    static let historyTurns = 4

    static let instructions = """
        You answer questions about a notebook of the user's sources: documents, web pages, notes \
        and meeting transcripts. Use only the numbered sources given, and after each fact cite its \
        source number in brackets, like [2]. If the sources don't cover the question, say the \
        notebook doesn't cover it; never guess or use outside knowledge. Sources can disagree, as \
        when a newer one changes what an older one says: then give what each says, with its \
        citation. Be brief: one to four sentences. Only when listing several things, put each on \
        its own line starting with "- ".
        """

    /// The passages that best match the question, then what each source is about (its digest, for
    /// broad questions like "what do these have in common?"), then more passages, in that order
    /// until the budget is spent. With no match and no digests, the start of each source.
    public static func sources(
        question: String,
        history: [MeetingChatTurn] = [],
        passages: [SearchPassage],
        titles: [UUID: String],
        digests: [SourceDigest] = [],
        expand: (String) -> [(term: String, weight: Double)] = { _ in [] },
        wordBudget: Int = 1_000,
        limit: Int = 8
    ) -> [Source] {
        var result: [(noteID: UUID, text: String)] = []
        var seen = Set<String>()
        var words = 0
        @discardableResult
        func add(_ noteID: UUID, _ text: String) -> Bool {
            let text = NotesQuestion.excerpt(text.trimmingCharacters(in: .whitespacesAndNewlines), maxWords: wordsPerExcerpt)
            let count = text.split(whereSeparator: \.isWhitespace).count
            guard result.count < limit, count > 0, words + count <= wordBudget, seen.insert(text).inserted else { return false }
            words += count
            result.append((noteID, text))
            return true
        }

        // A title on its own says little; the digest or the text says more.
        let body = passages.filter { $0.source != .title }
        let asked = history.last { $0.role == .user }?.text ?? ""
        // The question's own matches first; then, for a follow-up like "why then?", what the last
        // question matched. The trailing space tells search the last word is finished, not half-typed.
        let index = SearchIndex(passages: body)
        var hits = index.search("\(question) ", limit: 30, perNote: 4, expand: expand)
        if !asked.isEmpty { hits += index.search("\(question) \(asked) ", limit: 30, perNote: 4, expand: expand) }
        let reserved = min(3, digests.count)
        var rest = hits[...]
        while result.count < limit - reserved, let hit = rest.popFirst() {
            add(hit.passage.noteID, hit.passage.text)
        }
        // Digests of the sources that matched first.
        let matched = hits.map(\.passage.noteID)
        let ordered = digests.sorted { (matched.firstIndex(of: $0.noteID) ?? .max) < (matched.firstIndex(of: $1.noteID) ?? .max) }
        for digest in ordered {
            add(digest.noteID, ([digest.summary] + digest.keyPoints.map { "- \($0)" }).joined(separator: "\n"))
        }
        for hit in rest { add(hit.passage.noteID, hit.passage.text) }

        if result.isEmpty {
            var openings: [UUID: String] = [:]
            var order: [UUID] = []
            for passage in body where openings[passage.noteID, default: ""].split(whereSeparator: \.isWhitespace).count < wordsPerExcerpt {
                if openings[passage.noteID] == nil { order.append(passage.noteID) }
                openings[passage.noteID, default: ""] += passage.text + "\n"
            }
            order.forEach { add($0, openings[$0] ?? "") }
        }

        // One number for each note, however many of its excerpts are given, so a citation names a
        // source and the numbers never outrun the sources.
        var sources: [Source] = []
        for excerpt in result {
            if let index = sources.firstIndex(where: { $0.noteID == excerpt.noteID }) {
                let source = sources[index]
                sources[index] = Source(number: source.number, noteID: source.noteID, title: source.title,
                                        text: source.text + "\n…\n" + excerpt.text)
            } else {
                sources.append(Source(number: sources.count + 1, noteID: excerpt.noteID,
                                      title: titles[excerpt.noteID] ?? "Untitled", text: excerpt.text))
            }
        }
        return sources
    }

    static func prompt(question: String, sources: [Source], history: [MeetingChatTurn]) -> String {
        let listed = sources.map { "[\($0.number)] \($0.title)\n\($0.text)" }
        let conversation = history.suffix(historyTurns).map { turn in
            "\(turn.role == .user ? "User" : "You"): \(uncited(turn.text).prefix(words: 80))"
        }
        return """
            SOURCES:
            \(listed.joined(separator: "\n\n"))

            CONVERSATION SO FAR:
            \(conversation.isEmpty ? "(none)" : conversation.joined(separator: "\n"))

            QUESTION: \(question)
            """
    }

    /// What the model found in the sources, each thing said once with every source that says it,
    /// in the order found. Findings naming a source that wasn't given, or saying it says nothing,
    /// are dropped.
    static func claims(_ findings: [(source: Int, says: String)], count: Int) -> [(says: String, sources: [Int])] {
        var claims: [(key: String, says: String, sources: [Int])] = []
        for finding in findings where (1...max(1, count)).contains(finding.source) {
            let says = finding.says.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-•")))
            let key = says.lowercased().filter { $0.isLetter || $0.isNumber }
            guard !key.isEmpty, key != "nothing" else { continue }
            if let index = claims.firstIndex(where: { $0.key == key }) {
                if !claims[index].sources.contains(finding.source) { claims[index].sources.append(finding.source) }
            } else {
                claims.append((key, says, [finding.source]))
            }
        }
        return claims.map { (says: $0.says, sources: $0.sources.sorted()) }
    }

    /// The model's answer, or what each source says: where they disagree, since the on-device model
    /// notes both sides and then often answers with one, or with only the citations. An answer
    /// citing nothing cites the sources the model noted.
    static func answer(_ answer: String, claims: [(says: String, sources: [Int])], disagree: Bool, count: Int) -> String {
        let listed = claims.map { NotebookSummary.citing($0.says.hasSuffix(".") ? $0.says : $0.says + ".", $0.sources) }
        if disagree, listed.count > 1 {
            return (["The sources differ:"] + listed.map { "- " + $0 }).joined(separator: "\n")
        }
        guard !listed.isEmpty else { return answer }
        guard uncited(answer).contains(where: \.isLetter) else {
            return listed.count == 1 ? listed[0] : listed.map { "- " + $0 }.joined(separator: "\n")
        }
        return NotesQuestion.cited(in: answer, count: count).isEmpty
            ? NotebookSummary.citing(answer, Set(claims.flatMap(\.sources)).sorted()) : answer
    }

    /// The answer without a list of source numbers in parentheses, "(1, 2, 3)", which the model
    /// sometimes writes beside the `[n]` markers. Only a list of two or more numbers that all name
    /// a given source goes, so "(2024)" and "(3)" stay.
    static func withoutNumberLists(_ answer: String, count: Int) -> String {
        guard count > 1, let pattern = try? Regex(#"\s*\(\s*(\d+(?:\s*[,;]\s*\d+)+)\s*\)"#) else { return answer }
        var result = answer
        for match in answer.matches(of: pattern).reversed() {
            guard let list = match.output[1].substring else { continue }
            let numbers = list.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if numbers.allSatisfy({ (1...count).contains($0) }) { result.removeSubrange(match.range) }
        }
        return result
    }

    /// An earlier answer without its `[n]` markers, which pointed at that turn's sources, not these.
    static func uncited(_ text: String) -> String {
        guard let pattern = try? Regex(#"\s*\[\s*\d+(?:\s*[,;]\s*\d+)*\s*\]"#) else { return text }
        return text.replacing(pattern, with: "")
    }
}

#if canImport(FoundationModels)
/// Answers questions about a notebook from its sources with Apple's on-device model, citing them.
@available(iOS 26, macOS 26, *)
public struct OnDeviceNotebookChat: Sendable {
    public init() {}

    /// `history` is the conversation so far, oldest first. Cite-able `[n]` markers in the answer
    /// refer to `sources`.
    public func answer(question: String, sources: [NotebookChat.Source], history: [MeetingChatTurn] = []) async throws -> String {
        guard !sources.isEmpty else { throw OnDeviceAIError.emptyNotebook }
        let session = LanguageModelSession(instructions: NotebookChat.instructions)
        let prompt = NotebookChat.prompt(question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                                         sources: sources, history: history)
        let reading = try await session.respond(to: prompt, generating: Reading.self).content
        let claims = NotebookChat.claims(reading.findings.map { (source: $0.source, says: $0.says) }, count: sources.count)
        let disagree = try await disagree(claims, question: question)
        let answer = NotebookChat.answer(
            NotebookChat.withoutNumberLists(reading.answer.trimmingCharacters(in: .whitespacesAndNewlines), count: sources.count),
            claims: claims, disagree: disagree, count: sources.count)
        guard !answer.isEmpty else { throw OnDeviceAIError.emptyResponse }
        return answer
    }

    private func disagree(_ claims: [(says: String, sources: [Int])], question: String) async throws -> Bool {
        guard claims.count > 1, Set(claims.flatMap(\.sources)).count > 1 else { return false }
        return try await Self.compare(claims, question: question) == .conflict
    }

    /// Whether the sources' claims agree, conflict, or are about different things. Asked on its own,
    /// of just the claims: judged in the same answer that notes them, the on-device model often
    /// misses a conflict, or sees one between the same words.
    static func compare(_ claims: [(says: String, sources: [Int])], question: String) async throws -> Comparison {
        let session = LanguageModelSession()
        let prompt = """
            QUESTION: \(question)

            \(claims.map { "Source \($0.sources.map(String.init).joined(separator: ", ")): \($0.says)" }.joined(separator: "\n"))
            """
        return try await session.respond(to: prompt, generating: Judgment.self).content.verdict
    }

    /// What each source says comes first, so the model reads all of them, a newer one that
    /// disagrees included, before it answers.
    @Generable
    struct Reading {
        @Guide(description: "One for each source, starting with 1 and going in order: what it says that bears on the question, even in other words, or nothing")
        var findings: [Finding]
        @Guide(description: "The answer in one to four sentences, with each fact's source number in brackets after it")
        var answer: String
    }

    @Generable
    enum Comparison {
        case agree, conflict, unrelated
    }

    @Generable
    struct Judgment {
        // The model sees only the cases' names, so their meanings go here.
        @Guide(description: "agree if the sources give the same value for the same thing; conflict if they give different values for the same thing, such as two prices for one fee; unrelated if they speak about different things")
        var verdict: Comparison
    }

    @Generable
    struct Finding {
        @Guide(description: "The source's number")
        var source: Int
        @Guide(description: "What it says, in a sentence")
        var says: String
    }
}
#endif
