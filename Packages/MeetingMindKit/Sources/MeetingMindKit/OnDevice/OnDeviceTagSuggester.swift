import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tag suggestions: the prompt and the clean-up around the on-device model.
public enum NoteTags {
    static let maxNoteWords = 1_200
    /// Enough of the user's vocabulary to reuse, without crowding out the note.
    static let maxExistingTags = 60

    static let instructions = """
        You suggest 2 to 5 short topic tags for a note, so it can be found and grouped with \
        related notes later. Tags name what the note is about (subject, project, course, place), \
        never its format: no tags like "notes", "meeting" or "todo". Lowercase, 1 or 2 words each, \
        no # symbol. If one of the user's existing tags fits, reuse it exactly instead of a \
        near-duplicate.
        """

    static func prompt(title: String, notes: String, existingTags: [String]) -> String {
        let existing = existingTags.prefix(maxExistingTags).joined(separator: ", ")
        return """
            EXISTING TAGS: \(existing.isEmpty ? "(none yet)" : existing)

            TITLE: \(title)

            NOTES:
            \(notes.prefix(words: maxNoteWords))
            """
    }

    /// Lowercased, `#` stripped, duplicates dropped, at most five.
    static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        let cleaned = tags.compactMap { raw -> String? in
            let tag = raw.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines)).lowercased()
            guard !tag.isEmpty, seen.insert(tag).inserted else { return nil }
            return tag
        }
        return Array(cleaned.prefix(5))
    }
}

#if canImport(FoundationModels)
/// Suggests topic tags for a note with Apple's on-device model. `existingTags` are the user's tags
/// on other notes; the model is told to reuse them, so one topic isn't tagged three ways.
@available(iOS 26, macOS 26, *)
public struct OnDeviceTagSuggester: Sendable {
    public init() {}

    public func tags(title: String, notes: String, existingTags: [String] = []) async throws -> [String] {
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { throw OnDeviceAIError.emptyNotes }

        let session = LanguageModelSession(instructions: NoteTags.instructions)
        let prompt = NoteTags.prompt(title: title, notes: notes, existingTags: existingTags)
        return NoteTags.normalized(try await session.respond(to: prompt, generating: Tags.self).content.tags)
    }

    @Generable
    struct Tags {
        @Guide(description: "Lowercase topic tags, 1 or 2 words each", .count(2...5))
        var tags: [String]
    }
}
#endif
