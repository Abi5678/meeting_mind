import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One message in a conversation about a meeting.
public struct MeetingChatTurn: Equatable, Sendable {
    public enum Role: String, Sendable { case user, assistant }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// "Ask this meeting": picks the parts of a meeting that fit the on-device model and builds the prompt.
public enum MeetingChat {
    /// About 1,350 tokens, leaving room for the instructions, the conversation and the answer.
    static let wordBudget = 1_000
    static let wordsPerExcerpt = 120
    /// Earlier turns sent along, so follow-ups like "who owns that?" make sense.
    static let historyTurns = 4

    static let instructions = """
        You answer questions about one meeting, using only the excerpts given from its notes and \
        its transcript. The transcript comes from automatic speech recognition, so expect misheard \
        words and no speaker names. If the excerpts don't cover the question, say the meeting \
        didn't cover it; never guess or use outside knowledge. Be brief: a sentence or two. Only \
        when listing several things, put each on its own line starting with "- ". When it helps, \
        quote the meeting's own words.
        """

    /// The whole meeting when it fits; otherwise the parts most likely to answer `question`, in the
    /// order they came, topped up from the start (a meeting note opens with its summary).
    static func excerpts(
        question: String, transcript: String, notes: String, history: [MeetingChatTurn], wordBudget: Int = wordBudget
    ) -> [String] {
        // A recorded meeting's note holds its transcript too; don't send it twice.
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let sources = transcript.isEmpty || notes.contains(transcript) ? [notes] : [notes, transcript]
        let chunks = sources.flatMap { TranscriptChunker.chunks($0, maxWords: wordsPerExcerpt) }
        let sizes = chunks.map { $0.split(whereSeparator: \.isWhitespace).count }
        guard sizes.reduce(0, +) > wordBudget else { return chunks }

        let ids = chunks.map { _ in UUID() }
        let index = SearchIndex(passages: zip(ids, chunks).map { SearchPassage(noteID: $0, source: .title, text: $1) })
        let asked = history.last { $0.role == .user }?.text ?? ""
        // The trailing space tells search the last word is finished, not half-typed.
        let ranked = index.search("\(question) \(asked) ", limit: chunks.count).compactMap { ids.firstIndex(of: $0.passage.noteID) }

        var chosen = Set<Int>()
        var words = 0
        for i in ranked + chunks.indices where !chosen.contains(i) && words + sizes[i] <= wordBudget {
            chosen.insert(i)
            words += sizes[i]
        }
        return chunks.indices.filter(chosen.contains).map { chunks[$0] }
    }

    static func prompt(question: String, excerpts: [String], history: [MeetingChatTurn]) -> String {
        let conversation = history.suffix(historyTurns).map { turn in
            "\(turn.role == .user ? "User" : "You"): \(turn.text.prefix(words: 80))"
        }
        return """
            EXCERPTS FROM THE MEETING:
            \(excerpts.joined(separator: "\n\n"))

            CONVERSATION SO FAR:
            \(conversation.isEmpty ? "(none)" : conversation.joined(separator: "\n"))

            QUESTION: \(question)
            """
    }
}

#if canImport(FoundationModels)
/// Answers questions about a meeting from its transcript and the notes on it, with Apple's
/// on-device model.
@available(iOS 26, macOS 26, *)
public struct OnDeviceMeetingChat: Sendable {
    public init() {}

    /// `history` is the conversation so far, oldest first.
    public func answer(
        question: String, transcript: String, notes: String = "", history: [MeetingChatTurn] = []
    ) async throws -> String {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpts = MeetingChat.excerpts(question: question, transcript: transcript, notes: notes, history: history)
        guard excerpts.contains(where: { !$0.isEmpty }) else { throw OnDeviceAIError.emptyMeeting }

        let session = LanguageModelSession(instructions: MeetingChat.instructions)
        let prompt = MeetingChat.prompt(question: question, excerpts: excerpts, history: history)
        let answer = try await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw OnDeviceAIError.emptyResponse }
        return answer
    }
}
#endif
