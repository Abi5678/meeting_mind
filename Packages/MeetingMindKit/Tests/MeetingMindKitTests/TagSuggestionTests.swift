import Foundation
import Testing

@testable import MeetingMindKit

@Suite("Tag suggestions")
struct TagSuggestionTests {
    private func makeClient(transport: StubTransport) -> GeminiClient {
        GeminiClient(apiKey: "test-key", transport: transport, sleep: DelayRecorder().sleep)
    }

    @Test("Tags come back lowercased, without #, de-duplicated and capped at five")
    func normalizesTags() async throws {
        let json = ##"{"tags":[" Biology","#photosynthesis","biology","Plants","exams","study","extra"]}"##
        let transport = StubTransport([.response(Fixture.success(text: json))])
        let tags = try await makeClient(transport: transport).suggestTags(title: "Photosynthesis", notes: "Light reactions.")
        #expect(tags == ["biology", "photosynthesis", "plants", "exams", "study"])
    }

    @Test("The request sends the tags schema and a prompt with the title, notes and existing tags")
    func requestShape() async throws {
        let transport = StubTransport([.response(Fixture.success(text: #"{"tags":["biology"]}"#))])
        _ = try await makeClient(transport: transport)
            .suggestTags(title: "Photosynthesis", notes: "Light reactions.", existingTags: ["biology", "exams"])

        let request = await transport.received[0]
        let properties = (request.generationConfig["responseSchema"] as? [String: Any])?["properties"] as? [String: Any]
        #expect(properties?["tags"] != nil)
        #expect(request.promptText.contains("TITLE: Photosynthesis"))
        #expect(request.promptText.contains("Light reactions."))
        #expect(request.promptText.contains("EXISTING TAGS: biology, exams"))
    }

    @Test("Blank notes fail before any network call")
    func emptyNotes() async {
        let transport = StubTransport([])
        await #expect(throws: GeminiError.emptyNotes) {
            try await makeClient(transport: transport).suggestTags(title: "Empty", notes: " \n")
        }
        #expect(await transport.callCount == 0)
    }
}
