import Foundation

/// "Ask your notes": the search hits for a question become numbered sources, a model answers from
/// them alone, and the `[n]` markers in its answer lead back to the notes.
public enum NotesQuestion {
    /// One numbered source handed to the model.
    public struct Source: Sendable, Equatable {
        public let number: Int
        public let noteTitle: String
        public let hit: SearchHit
    }

    /// The best hits, numbered from 1, that fit in `wordBudget` words. Apple's on-device model reads
    /// about 4,000 tokens with its answer, so the default leaves room for both.
    public static func sources(
        from hits: [SearchHit], titles: [UUID: String], wordBudget: Int = 1000, limit: Int = 8
    ) -> [Source] {
        var result: [Source] = []
        var words = 0
        for hit in hits where result.count < limit {
            let count = wordCount(excerpt(hit.passage.text))
            guard words + count <= wordBudget else { continue }
            words += count
            result.append(Source(number: result.count + 1, noteTitle: titles[hit.passage.noteID] ?? "Untitled", hit: hit))
        }
        return result
    }

    public static let instructions = """
        You answer questions about the user's own notes, meeting transcripts and the text in their \
        photos, using only the numbered sources given. After each fact, cite its source number in \
        brackets, like [2]. Never state anything the sources don't say. If they don't answer the \
        question, say you couldn't find it in the notes. Answer in one to four short sentences.
        """

    public static func prompt(question: String, sources: [Source]) -> String {
        let listed = sources.map { source in
            "[\(source.number)] \(source.noteTitle) — \(place(source.hit.passage.source))\n\(excerpt(source.hit.passage.text))"
        }
        return "Sources:\n\n" + listed.joined(separator: "\n\n") + "\n\nQuestion: " + question
    }

    /// Where a source sits in its note, in words the model can repeat.
    static func place(_ source: SearchPassage.Source) -> String {
        switch source {
        case .title: "note title"
        case .block: "note text"
        case let .transcript(start): "said in the meeting at " + Duration.seconds(start).formatted(.time(pattern: .minuteSecond))
        case .photo: "text in a photo"
        case .ink: "handwriting in the note"
        }
    }

    /// A citation in an answer: `[2]`, or `[1, 3]` for several sources at once.
    public struct Citation: Sendable, Equatable {
        public let range: Range<String.Index>
        public let numbers: [Int]
    }

    /// The citations in `answer` that name one of `count` sources. Numbers the model made up are
    /// dropped, and a marker left with none isn't a citation.
    public static func citations(in answer: String, count: Int) -> [Citation] {
        guard let pattern = try? Regex(#"\[\s*\d+(?:\s*[,;]\s*\d+)*\s*\]"#) else { return [] }
        return answer.matches(of: pattern).compactMap { match in
            let numbers = answer[match.range].split { !$0.isNumber }.compactMap { Int($0) }.filter { (1...count).contains($0) }
            return numbers.isEmpty ? nil : Citation(range: match.range, numbers: numbers)
        }
    }

    /// Source numbers in the order the answer first cites them.
    public static func cited(in answer: String, count: Int) -> [Int] {
        var seen = Set<Int>()
        return citations(in: answer, count: count).flatMap(\.numbers).filter { seen.insert($0).inserted }
    }

    /// A long passage (a photo of a page, say) is cut so one source can't use up the budget.
    static func excerpt(_ text: String, maxWords: Int = 150) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.count <= maxWords ? text : words.prefix(maxWords).joined(separator: " ") + " …"
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
