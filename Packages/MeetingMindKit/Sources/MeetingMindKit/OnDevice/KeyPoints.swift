#if canImport(NaturalLanguage)
import Foundation
import NaturalLanguage

/// Notes for a recording on a device without Apple Intelligence: the transcript's most telling
/// sentences, picked on the device with Apple's language tagger. They are the speakers' own words,
/// not a summary.
public enum KeyPoints {
    /// The picked sentences as the key points of an analysis with nothing else written; nil when
    /// the transcript has no sentence worth picking.
    public static func analysis(of transcript: String) -> MeetingAnalysis? {
        let points = sentences(in: transcript)
        guard !points.isEmpty else { return nil }
        return MeetingAnalysis(summary: "", keyDecisions: [], actionItems: [],
                               followUpEmail: .init(subject: "", body: ""), keyPoints: points)
    }

    /// The sentences that between them cover what was talked about most, in the order they were
    /// said: three for a short memo, up to eight for a long meeting. A sentence scores by how often
    /// the recording comes back to its nouns; once picked, its nouns count for less, so the next
    /// pick covers something else.
    static func sentences(in transcript: String) -> [String] {
        // Speaker labels ("Speaker 2: ") aren't part of what was said.
        let text = transcript.replacingOccurrences(of: #"(?m)^Speaker \d+: "#, with: "", options: .regularExpression)
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text

        var sentences: [(text: String, words: Int, nouns: Set<String>)] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            var words = 0
            var nouns = Set<String>()
            tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, word in
                words += 1
                if tag == .noun {
                    let lemma = tagger.tag(at: word.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? String(text[word])
                    nouns.insert(lemma.lowercased())
                }
                return true
            }
            sentences.append((text[range].trimmingCharacters(in: .whitespacesAndNewlines), words, nouns))
            return true
        }

        var weight: [String: Double] = [:]
        for sentence in sentences {
            for noun in sentence.nouns { weight[noun, default: 0] += 1 }
        }
        // Too short to stand on its own, or too long to read as one point.
        let candidates = sentences.indices.filter { (6...50).contains(sentences[$0].words) }
        func score(_ i: Int) -> Double {
            sentences[i].nouns.reduce(0) { $0 + weight[$1, default: 0] } / Double(sentences[i].words).squareRoot()
        }

        var picked: [Int] = []
        for _ in 0..<min(8, max(3, candidates.count / 12)) {
            guard let best = candidates.filter({ !picked.contains($0) }).max(by: { score($0) < score($1) }),
                  score(best) > 0 else { break }
            picked.append(best)
            for noun in sentences[best].nouns { weight[noun]! /= 2 }
        }
        return picked.sorted().map { sentences[$0].text }
    }
}
#endif
