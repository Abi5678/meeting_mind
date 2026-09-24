import Foundation

/// A stretch of a note that search can land on: the title, a text block, a moment of a
/// recorded meeting, or the words in a photo.
public struct SearchPassage: Sendable, Equatable {
    public enum Source: Sendable, Hashable {
        case title
        case block(UUID)
        /// Seconds into the note's recording.
        case transcript(start: TimeInterval)
        case photo(UUID)
    }

    public let noteID: UUID
    public let source: Source
    public let text: String
    /// For a transcript passage, where in `text` each timed piece begins, so a hit can seek to
    /// the piece it matched rather than the start of the passage.
    let marks: [(offset: Int, start: TimeInterval)]

    public init(noteID: UUID, source: Source, text: String) {
        self.init(noteID: noteID, source: source, text: text, marks: [])
    }

    init(noteID: UUID, source: Source, text: String, marks: [(offset: Int, start: TimeInterval)]) {
        self.noteID = noteID
        self.source = source
        self.text = text
        self.marks = marks
    }

    public static func == (a: SearchPassage, b: SearchPassage) -> Bool {
        a.noteID == b.noteID && a.source == b.source && a.text == b.text
    }

    /// The passage pointed at the moment that holds `offset`, for transcripts.
    func at(offset: Int) -> SearchPassage {
        guard let mark = marks.last(where: { $0.offset <= offset }) else { return self }
        return SearchPassage(noteID: noteID, source: .transcript(start: mark.start), text: text, marks: marks)
    }

    /// Everything searchable in one note.
    /// - Parameters:
    ///   - photoText: recognized text per photo id; photos with none are skipped.
    ///   - transcript: timed pieces of the note's recording, grouped into passages of about
    ///     `wordsPerPassage` words so a hit can seek the audio.
    ///   - transcriptBlockText: the text of the block that holds the same transcript untimed; it is
    ///     skipped when timed pieces exist so each moment is found once, with its time.
    public static func passages(
        noteID: UUID,
        title: String,
        blocks: [Block],
        photoText: [UUID: String] = [:],
        transcript: [TranscriptPiece] = [],
        transcriptBlockText: String? = nil,
        wordsPerPassage: Int = 50
    ) -> [SearchPassage] {
        var result: [SearchPassage] = []
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(SearchPassage(noteID: noteID, source: .title, text: title))
        }
        let skip = transcript.isEmpty ? nil : transcriptBlockText?.trimmingCharacters(in: .whitespacesAndNewlines)
        for block in blocks {
            if case let .image(id) = block.type {
                if let text = photoText[id], !text.isEmpty {
                    result.append(SearchPassage(noteID: noteID, source: .photo(id), text: text))
                }
                continue
            }
            let text = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != skip else { continue }
            // A long paragraph (an untimed transcript, a pasted article) is split so its snippet
            // shows the part that matched.
            for piece in wordWindows(text, size: wordsPerPassage * 2) {
                result.append(SearchPassage(noteID: noteID, source: .block(block.id), text: piece))
            }
        }
        var words = 0
        var group: [TranscriptPiece] = []
        func flush() {
            guard let first = group.first else { return }
            var text = ""
            var marks: [(offset: Int, start: TimeInterval)] = []
            for piece in group {
                if !text.isEmpty { text += " " }
                marks.append((text.count, piece.start))
                text += piece.text
            }
            result.append(SearchPassage(noteID: noteID, source: .transcript(start: first.start), text: text, marks: marks))
            group = []
            words = 0
        }
        for piece in transcript where !piece.text.isEmpty {
            group.append(piece)
            words += piece.text.split(whereSeparator: \.isWhitespace).count
            if words >= wordsPerPassage { flush() }
        }
        flush()
        return result
    }

    private static func wordWindows(_ text: String, size: Int) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count > size else { return [text] }
        return stride(from: 0, to: words.count, by: size).map {
            words[$0 ..< min($0 + size, words.count)].joined(separator: " ")
        }
    }
}

public struct SearchHit: Sendable, Equatable {
    public let passage: SearchPassage
    public let score: Double
    /// The part of the passage around the first match, with `…` where it was cut.
    public let snippet: String
    /// The words in `snippet` that matched, for bolding.
    public let matches: [Range<String.Index>]
}

/// Ranks passages for a query with BM25 over folded, lightly stemmed words. The last query word
/// also matches as a prefix, so results keep up while typing, and each word can bring related
/// words (`expand`) at a lower weight, which is how "groceries" finds "shopping".
public struct SearchIndex: Sendable {
    private struct Entry: Sendable {
        let passage: SearchPassage
        let counts: [String: Int]
        let length: Int
    }

    private let entries: [Entry]
    private let documentFrequency: [String: Int]
    private let averageLength: Double

    public init(passages: [SearchPassage]) {
        var frequency: [String: Int] = [:]
        entries = passages.map { passage in
            let terms = SearchText.terms(passage.text)
            let counts = terms.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            counts.keys.forEach { frequency[$0, default: 0] += 1 }
            return Entry(passage: passage, counts: counts, length: terms.count)
        }
        documentFrequency = frequency
        averageLength = entries.isEmpty ? 1 : max(1, Double(entries.map(\.length).reduce(0, +)) / Double(entries.count))
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// - Parameters:
    ///   - expand: related words for a query word, each with a weight in 0...1.
    ///   - perNote: at most this many hits from any one note, so one long note can't fill the list.
    public func search(
        _ query: String,
        limit: Int = 50,
        perNote: Int = 3,
        expand: (String) -> [(term: String, weight: Double)] = { _ in [] }
    ) -> [SearchHit] {
        var words = SearchText.terms(query)
        let meaningful = words.filter { !SearchText.stopWords.contains($0) }
        if !meaningful.isEmpty { words = meaningful }
        guard !words.isEmpty else { return [] }

        // Each query word becomes the set of index terms that count for it, with their weights.
        let lastIsPartial = query.last.map { !$0.isWhitespace && !$0.isPunctuation } ?? false
        let variants: [[String: Double]] = words.enumerated().map { index, word in
            var terms: [String: Double] = [word: 1]
            if index == words.count - 1, lastIsPartial, word.count >= 2 {
                for term in documentFrequency.keys where term.count > word.count && term.hasPrefix(word) {
                    terms[term] = max(terms[term] ?? 0, 0.8)
                }
                // A half-typed "-ing" word is on its way to one stored as its root: "bookin" → "book".
                for ending in ["g", "ng"] where (word + ending).hasSuffix("ing") {
                    let root = SearchText.stem(word + ending)
                    if root != word + ending { terms[root] = max(terms[root] ?? 0, 0.8) }
                }
            }
            for (term, weight) in expand(word) {
                for stemmed in SearchText.terms(term) where terms[stemmed] == nil {
                    terms[stemmed] = min(weight, 0.6)
                }
            }
            return terms
        }

        let total = Double(entries.count)
        func idf(_ term: String) -> Double {
            let n = Double(documentFrequency[term] ?? 0)
            return log(1 + (total - n + 0.5) / (n + 0.5))
        }

        var scored: [(entry: Entry, score: Double, matched: Set<String>)] = []
        for entry in entries {
            var score = 0.0
            var covered = 0.0
            var matched: Set<String> = []
            for terms in variants {
                var best = 0.0
                var bestWeight = 0.0
                for (term, weight) in terms {
                    guard let count = entry.counts[term] else { continue }
                    let tf = Double(count)
                    let norm = tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * Double(entry.length) / averageLength))
                    best = max(best, weight * idf(term) * norm)
                    bestWeight = max(bestWeight, weight)
                    matched.insert(term)
                }
                score += best
                covered += bestWeight
            }
            guard score > 0 else { continue }
            // Passages that answer every word come before ones that answer some of them.
            let coverage = covered / Double(variants.count)
            score *= coverage * coverage
            if entry.passage.source == .title { score *= 1.5 }
            scored.append((entry, score, matched))
        }
        scored.sort { $0.score > $1.score }

        var perNoteCount: [UUID: Int] = [:]
        var hits: [SearchHit] = []
        for item in scored where hits.count < limit {
            let noteID = item.entry.passage.noteID
            guard perNoteCount[noteID, default: 0] < perNote else { continue }
            perNoteCount[noteID, default: 0] += 1
            var passage = item.entry.passage
            let (snippet, ranges) = SearchText.snippet(of: passage.text, matching: item.matched)
            if !passage.marks.isEmpty,
               let first = SearchText.words(in: passage.text).first(where: { item.matched.contains(SearchText.stem(SearchText.fold(String(passage.text[$0])))) }) {
                passage = passage.at(offset: passage.text.distance(from: passage.text.startIndex, to: first.lowerBound))
            }
            hits.append(SearchHit(passage: passage, score: item.score, snippet: snippet, matches: ranges))
        }
        return hits
    }
}

enum SearchText {
    static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "did", "do", "for", "from", "how", "i", "in", "is",
        "it", "me", "my", "of", "on", "or", "our", "so", "that", "the", "their", "this", "to", "was", "we",
        "what", "when", "where", "which", "who", "why", "with", "you",
    ]

    /// Lowercased, accent-free, lightly stemmed words.
    static func terms(_ text: String) -> [String] {
        words(in: text).map { stem(fold(String(text[$0]))) }
    }

    static func words(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
    }

    static func fold(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Just enough to make plurals, possessives and -ing forms meet their root, after Porter:
    /// "booking" and "book", "planning" and "plan", "making" and "make" come out the same.
    static func stem(_ word: String) -> String {
        var w = word
        if w.hasSuffix("'s") || w.hasSuffix("’s") { w.removeLast(2) }
        guard w.count > 3, w.allSatisfy(\.isLetter) else { return w }
        if w.hasSuffix("ies") { w = String(w.dropLast(3)) + "y" }
        else if w.hasSuffix("sses") || w.hasSuffix("xes") || w.hasSuffix("ches") || w.hasSuffix("shes") { w.removeLast(2) }
        else if w.hasSuffix("s"), !w.hasSuffix("ss"), !w.hasSuffix("us"), !w.hasSuffix("is") { w.removeLast() }

        if w.hasSuffix("ing") {
            var root = Array(w.dropLast(3))
            if root.count >= 3, root.indices.contains(where: { isVowel(root, $0) }) {
                let last = root.count - 1
                if root.count > 3, root[last] == root[last - 1], !isVowel(root, last), !"lsz".contains(root[last]) {
                    root.removeLast()  // planning → plan
                } else if measure(root) == 1, endsShortSyllable(root) {
                    root.append("e")  // making → make
                }
                w = String(root)
            }
        }
        // A silent e goes, so "schedule" meets "scheduling"; "note" keeps its e and stays apart from "not".
        if w.count > 3, w.hasSuffix("e") {
            let root = Array(w.dropLast())
            let m = measure(root)
            if m > 1 || (m == 1 && !endsShortSyllable(root)) { w.removeLast() }
        }
        return w
    }

    private static func isVowel(_ w: [Character], _ i: Int) -> Bool {
        switch w[i] {
        case "a", "e", "i", "o", "u": true
        case "y": i > 0 && !isVowel(w, i - 1)
        default: false
        }
    }

    /// Porter's measure: the number of vowel-then-consonant runs ("book" 1, "open" 2).
    private static func measure(_ w: [Character]) -> Int {
        var m = 0
        for i in w.indices.dropFirst() where isVowel(w, i - 1) && !isVowel(w, i) { m += 1 }
        return m
    }

    /// Consonant, vowel, consonant (not w, x or y) at the end, as in "mak" or "hop".
    private static func endsShortSyllable(_ w: [Character]) -> Bool {
        let n = w.count
        return n >= 3 && !isVowel(w, n - 3) && isVowel(w, n - 2) && !isVowel(w, n - 1) && !"wxy".contains(w[n - 1])
    }

    /// About `width` characters around the first matching word, cut at word boundaries.
    static func snippet(of text: String, matching terms: Set<String>, width: Int = 160) -> (String, [Range<String.Index>]) {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let words = words(in: flat)
        let hits = words.filter { terms.contains(stem(fold(String(flat[$0])))) }
        guard flat.count > width else { return (flat, hits) }

        let anchor = hits.first?.lowerBound ?? flat.startIndex
        let lead = width / 4
        var start = flat.index(anchor, offsetBy: -lead, limitedBy: flat.startIndex) ?? flat.startIndex
        if start != flat.startIndex, let word = words.first(where: { $0.lowerBound >= start }) { start = word.lowerBound }
        var end = flat.index(start, offsetBy: width, limitedBy: flat.endIndex) ?? flat.endIndex
        if end != flat.endIndex, let word = words.last(where: { $0.upperBound <= end }) { end = word.upperBound }

        let prefix = start == flat.startIndex ? "" : "…"
        let suffix = end == flat.endIndex ? "" : "…"
        let snippet = prefix + flat[start ..< end] + suffix
        // Re-find the matches in the snippet, whose indices differ from the source's.
        let ranges = self.words(in: snippet).filter { terms.contains(stem(fold(String(snippet[$0])))) }
        return (snippet, ranges)
    }
}
