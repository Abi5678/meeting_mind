import Foundation
import Testing

@testable import MeetingMindKit

@Suite("Tag suggestions")
struct TagSuggestionTests {
    @Test("Tags come back lowercased, without #, de-duplicated and capped at five")
    func normalizesTags() {
        let tags = NoteTags.normalized([" Biology", "#photosynthesis", "biology", "Plants", "exams", "study", "extra"])
        #expect(tags == ["biology", "photosynthesis", "plants", "exams", "study"])
    }

    @Test("The prompt has the title, notes and existing tags")
    func prompt() {
        let prompt = NoteTags.prompt(title: "Photosynthesis", notes: "Light reactions.", existingTags: ["biology", "exams"])
        #expect(prompt.contains("TITLE: Photosynthesis"))
        #expect(prompt.contains("Light reactions."))
        #expect(prompt.contains("EXISTING TAGS: biology, exams"))
        #expect(NoteTags.prompt(title: "T", notes: "N", existingTags: []).contains("EXISTING TAGS: (none yet)"))
    }
}
