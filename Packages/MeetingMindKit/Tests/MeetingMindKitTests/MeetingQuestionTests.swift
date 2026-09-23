import Foundation
import Testing

@testable import MeetingMindKit

@Suite("Meeting questions")
struct MeetingQuestionTests {
    private func makeClient(transport: StubTransport) -> GeminiClient {
        GeminiClient(apiKey: "test-key", transport: transport, sleep: DelayRecorder().sleep)
    }

    @Test("The answer comes back trimmed")
    func returnsAnswer() async throws {
        let transport = StubTransport([.response(Fixture.success(text: #"{"answer":"  Priya owns the launch plan.\n"}"#))])
        let answer = try await makeClient(transport: transport)
            .answer(question: "Who owns the launch?", transcript: "Priya will own the launch plan.")
        #expect(answer == "Priya owns the launch plan.")
    }

    @Test("The request sends the answer schema and a prompt with the transcript, notes, history and question")
    func requestShape() async throws {
        let transport = StubTransport([.response(Fixture.success(text: #"{"answer":"Friday."}"#))])
        _ = try await makeClient(transport: transport).answer(
            question: " When is it due? ",
            transcript: "Priya will own the launch plan, due Friday.",
            notes: "Launch prep",
            history: [
                MeetingChatTurn(role: .user, text: "Who owns the launch?"),
                MeetingChatTurn(role: .assistant, text: "Priya."),
            ]
        )

        let request = await transport.received[0]
        let properties = (request.generationConfig["responseSchema"] as? [String: Any])?["properties"] as? [String: Any]
        #expect(properties?["answer"] != nil)
        #expect(request.promptText.contains("Priya will own the launch plan, due Friday."))
        #expect(request.promptText.contains("NOTES:\nLaunch prep"))
        #expect(request.promptText.contains("USER: Who owns the launch?\nASSISTANT: Priya."))
        #expect(request.promptText.contains("QUESTION: When is it due?"))
    }

    @Test("A first question says there is no conversation or notes yet")
    func firstQuestion() {
        let prompt = PromptBuilder.meetingQuestionPrompt(question: "Q", transcript: "T", notes: "", history: [])
        #expect(prompt.contains("NOTES:\n(none)"))
        #expect(prompt.contains("CONVERSATION SO FAR:\n(none)"))
    }

    @Test("A blank transcript fails before any network call")
    func emptyTranscript() async {
        let transport = StubTransport([])
        await #expect(throws: GeminiError.emptyTranscript) {
            try await makeClient(transport: transport).answer(question: "Anything?", transcript: " \n")
        }
        #expect(await transport.callCount == 0)
    }

    @Test("A blank answer is an empty response, not a blank chat bubble")
    func blankAnswer() async {
        let transport = StubTransport([.response(Fixture.success(text: #"{"answer":"  "}"#))])
        await #expect(throws: GeminiError.emptyResponse) {
            try await makeClient(transport: transport).answer(question: "Anything?", transcript: "Hello.")
        }
    }
}
