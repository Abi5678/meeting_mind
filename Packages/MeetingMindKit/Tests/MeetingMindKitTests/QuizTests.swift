import Foundation
import Testing

@testable import MeetingMindKit

@Suite("Quiz generation")
struct QuizTests {
    private func makeClient(transport: StubTransport, apiKey: String = "test-key") -> GeminiClient {
        GeminiClient(apiKey: apiKey, transport: transport, sleep: DelayRecorder().sleep)
    }

    private static let quiz = Quiz(
        title: "Cabin Trip Check",
        questions: [
            .init(prompt: "What needs booking?", options: ["Cabin", "Flight", "Car", "Boat"], answerIndex: 0,
                  explanation: "The notes say to book the cabin."),
            .init(prompt: "What snack is packed?", options: ["Chips", "Trail mix", "Fruit", "Nothing"], answerIndex: 1,
                  explanation: "Trail mix is on the packing list."),
        ]
    )

    private static func response(_ quiz: Quiz) -> HTTPResponse {
        Fixture.success(text: String(data: try! JSONEncoder().encode(quiz), encoding: .utf8)!)
    }

    @Test("A well-formed response decodes into a Quiz")
    func decodesQuiz() async throws {
        let transport = StubTransport([.response(Self.response(Self.quiz))])
        let quiz = try await makeClient(transport: transport).generateQuiz(fromNotes: "Book cabin. Pack trail mix.")
        #expect(quiz == Self.quiz)
    }

    @Test("The request sends the quiz schema and a prompt containing the notes and count")
    func requestShape() async throws {
        let transport = StubTransport([.response(Self.response(Self.quiz))])
        _ = try await makeClient(transport: transport).generateQuiz(fromNotes: "Book cabin.", questionCount: 3)

        let request = await transport.received[0]
        let schema = request.generationConfig["responseSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        #expect(properties?["questions"] != nil)
        #expect(properties?["summary"] == nil)

        let questions = properties?["questions"] as? [String: Any]
        let items = questions?["items"] as? [String: Any]
        let answerIndex = (items?["properties"] as? [String: Any])?["answerIndex"] as? [String: Any]
        #expect(answerIndex?["type"] as? String == "INTEGER")

        #expect(request.promptText.contains("Book cabin."))
        #expect(request.promptText.contains("Write 3 questions"))
    }

    @Test("Blank notes fail before any network call")
    func emptyNotes() async {
        let transport = StubTransport([])
        await #expect(throws: GeminiError.emptyNotes) {
            try await makeClient(transport: transport).generateQuiz(fromNotes: "  \n ")
        }
        let callCount = await transport.callCount
        #expect(callCount == 0)
    }

    @Test("No API key fails before any network call")
    func missingKey() async {
        let transport = StubTransport([])
        await #expect(throws: GeminiError.missingAPIKey) {
            try await makeClient(transport: transport, apiKey: "").generateQuiz(fromNotes: "Notes")
        }
    }

    @Test("Questions whose answer is not one of the options are dropped")
    func dropsUngradeableQuestions() async throws {
        var broken = Self.quiz
        broken.questions.append(.init(prompt: "Bad", options: ["A", "B"], answerIndex: 7, explanation: ""))
        broken.questions.append(.init(prompt: "Single", options: ["A"], answerIndex: 0, explanation: ""))

        let transport = StubTransport([.response(Self.response(broken))])
        let quiz = try await makeClient(transport: transport).generateQuiz(fromNotes: "Notes")
        #expect(quiz.questions == Self.quiz.questions)
    }

    @Test("A quiz with no gradeable questions surfaces as .notEnoughContent")
    func noPlayableQuestions() async throws {
        let empty = Quiz(title: "Nothing", questions: [])
        let text = String(data: try JSONEncoder().encode(empty), encoding: .utf8)!
        let transport = StubTransport([.response(Fixture.success(text: text))])
        await #expect(throws: GeminiError.notEnoughContent) {
            try await makeClient(transport: transport).generateQuiz(fromNotes: "Notes")
        }
    }

    @Test("A 429 on quiz generation is retried like analysis")
    func retries() async throws {
        let transport = StubTransport([.response(Fixture.failure(429)), .response(Self.response(Self.quiz))])
        _ = try await makeClient(transport: transport).generateQuiz(fromNotes: "Notes")
        let callCount = await transport.callCount
        #expect(callCount == 2)
    }
}
