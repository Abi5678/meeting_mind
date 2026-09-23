import Foundation

/// Cuts a transcript into pieces small enough for the on-device model's context window,
/// at sentence ends so no piece starts mid-thought.
public enum TranscriptChunker {
    public static func chunks(_ text: String, maxWords: Int) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
            // Speech without punctuation can be one endless "sentence"; split it by words.
            let words = sentence.split(whereSeparator: \.isWhitespace)
            for start in stride(from: 0, to: words.count, by: maxWords) {
                sentences.append(words[start ..< min(start + maxWords, words.count)].joined(separator: " "))
            }
        }

        var chunks: [String] = []
        var current: [String] = []
        var count = 0
        for sentence in sentences {
            let words = sentence.split(whereSeparator: \.isWhitespace).count
            if count + words > maxWords, !current.isEmpty {
                chunks.append(current.joined(separator: " "))
                current = []
                count = 0
            }
            current.append(sentence)
            count += words
        }
        if !current.isEmpty { chunks.append(current.joined(separator: " ")) }
        return chunks
    }
}
