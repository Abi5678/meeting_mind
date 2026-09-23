#if canImport(NaturalLanguage)
import NaturalLanguage

/// Words close in meaning to a search word, from the system's English word embedding, so a
/// search for "groceries" also finds "shopping". Whole-sentence embeddings were tried first and
/// scored unrelated text about as close as related text, so meaning enters search word by word.
///
/// Not thread-safe: use one per actor.
public final class RelatedWords {
    private let embedding: NLEmbedding?
    private var cache: [String: [(term: String, weight: Double)]] = [:]

    public init(language: NLLanguage = .english) {
        embedding = NLEmbedding.wordEmbedding(for: language)
    }

    /// Up to five neighbours, weighted 0...0.5 by closeness. Distances past 0.95 are mostly noise
    /// ("umbrella" → "demonstrator"), so they are left out.
    public func related(to word: String) -> [(term: String, weight: Double)] {
        if let cached = cache[word] { return cached }
        var result: [(term: String, weight: Double)] = []
        if let embedding, word.count > 2, embedding.contains(word) {
            result = embedding.neighbors(for: word, maximumCount: 5)
                .filter { $0.1 < 0.95 }
                .map { (term: $0.0, weight: min(0.5, 1.1 - $0.1)) }
        }
        cache[word] = result
        return result
    }
}
#endif
