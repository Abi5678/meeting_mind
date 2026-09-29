import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "Ask this notebook": picks what fits the on-device model from a notebook's sources, numbers it
/// for citing, and builds the prompt.
public enum NotebookChat {
    /// One numbered excerpt handed to the model. Several can come from the same note.
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
        notebook doesn't cover it; never guess or use outside knowledge. Be brief: one to four \
        sentences. Only when listing several things, put each on its own line starting with "- ".
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
        var result: [Source] = []
        var seen = Set<String>()
        var words = 0
        @discardableResult
        func add(_ noteID: UUID, _ text: String) -> Bool {
            let text = NotesQuestion.excerpt(text.trimmingCharacters(in: .whitespacesAndNewlines), maxWords: wordsPerExcerpt)
            let count = text.split(whereSeparator: \.isWhitespace).count
            guard result.count < limit, count > 0, words + count <= wordBudget, seen.insert(text).inserted else { return false }
            words += count
            result.append(Source(number: result.count + 1, noteID: noteID, title: titles[noteID] ?? "Untitled", text: text))
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
        return result
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
        let answer = try await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw OnDeviceAIError.emptyResponse }
        return answer
    }
}
#endif
