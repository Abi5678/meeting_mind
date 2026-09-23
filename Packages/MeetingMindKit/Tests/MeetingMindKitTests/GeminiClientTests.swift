import Foundation
import Testing

@testable import MeetingMindKit

@Suite("GeminiClient")
struct GeminiClientTests {
    private func makeClient(
        transport: StubTransport,
        recorder: DelayRecorder = DelayRecorder(),
        apiKey: String = "test-key",
        configuration: GeminiClient.Configuration = .init()
    ) -> GeminiClient {
        GeminiClient(
            apiKey: apiKey,
            configuration: configuration,
            transport: transport,
            sleep: recorder.sleep
        )
    }

    // MARK: - Happy path

    @Test("A well-formed response decodes into MeetingAnalysis")
    func decodesAnalysis() async throws {
        let transport = StubTransport([.response(Fixture.successAnalysis())])
        let analysis = try await makeClient(transport: transport).analyze(transcript: "We agreed to ship.")

        #expect(analysis == Fixture.analysis)
        #expect(analysis.actionItems[1].owner == "Unassigned")
        #expect(analysis.actionItems[1].due == nil)

        let callCount = await transport.callCount
        #expect(callCount == 1)
    }

    @Test("The request targets generateContent with the key, schema, and JSON mime type")
    func requestShape() async throws {
        let transport = StubTransport([.response(Fixture.successAnalysis())])
        _ = try await makeClient(transport: transport).analyze(transcript: "Hello.")

        let request = await transport.received[0]
        #expect(request.method == "POST")
        #expect(request.url.absoluteString ==
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
        #expect(request.headers["x-goog-api-key"] == "test-key")
        #expect(request.headers["Content-Type"] == "application/json")

        let config = request.generationConfig
        #expect(config["responseMimeType"] as? String == "application/json")
        #expect(config["responseSchema"] != nil)
        #expect(request.promptText.contains("Hello."))
    }

    @Test("The model name is configurable")
    func configurableModel() async throws {
        let transport = StubTransport([.response(Fixture.successAnalysis())])
        var configuration = GeminiClient.Configuration()
        configuration.model = "gemini-9-experimental"

        _ = try await makeClient(transport: transport, configuration: configuration).analyze(transcript: "Hi.")

        let request = await transport.received[0]
        #expect(request.url.absoluteString.hasSuffix("/models/gemini-9-experimental:generateContent"))
    }

    // MARK: - Guards

    @Test("No API key fails before any network call")
    func missingKey() async {
        let transport = StubTransport([])
        let client = makeClient(transport: transport, apiKey: "")

        await #expect(throws: GeminiError.missingAPIKey) {
            try await client.analyze(transcript: "Something was said.")
        }

        let callCount = await transport.callCount
        #expect(callCount == 0)
    }

    @Test("A blank transcript fails before any network call")
    func emptyTranscript() async {
        let transport = StubTransport([])
        let client = makeClient(transport: transport)

        await #expect(throws: GeminiError.emptyTranscript) {
            try await client.analyze(transcript: "   \n  ")
        }

        let callCount = await transport.callCount
        #expect(callCount == 0)
    }

    @Test("An over-long transcript is truncated before it is sent")
    func truncatesLongTranscript() async throws {
        let transport = StubTransport([.response(Fixture.successAnalysis())])
        let transcript = String(repeating: "a", count: 300_000) + "TAIL_MARKER"

        _ = try await makeClient(transport: transport).analyze(transcript: transcript)

        let request = await transport.received[0]
        #expect(!request.promptText.contains("TAIL_MARKER"))
        #expect(request.promptText.contains(String(repeating: "a", count: 1000)))
    }

    // MARK: - Retry

    @Test("A 429 is retried after the first backoff step")
    func retriesRateLimit() async throws {
        let transport = StubTransport([.response(Fixture.failure(429)), .response(Fixture.successAnalysis())])
        let recorder = DelayRecorder()

        let analysis = try await makeClient(transport: transport, recorder: recorder).analyze(transcript: "Hi.")
        #expect(analysis == Fixture.analysis)

        let callCount = await transport.callCount
        let delays = await recorder.delays
        #expect(callCount == 2)
        #expect(delays == [2])
    }

    @Test("Retry-After overrides the backoff schedule")
    func honorsRetryAfter() async throws {
        let transport = StubTransport([
            .response(Fixture.failure(429, headers: ["Retry-After": "7"])),
            .response(Fixture.successAnalysis()),
        ])
        let recorder = DelayRecorder()

        _ = try await makeClient(transport: transport, recorder: recorder).analyze(transcript: "Hi.")

        let delays = await recorder.delays
        #expect(delays == [7])
    }

    @Test("Retry-After is matched case-insensitively")
    func retryAfterCaseInsensitive() async throws {
        let transport = StubTransport([
            .response(Fixture.failure(503, headers: ["retry-after": "4"])),
            .response(Fixture.successAnalysis()),
        ])
        let recorder = DelayRecorder()
        let noFallback = GeminiClient.Configuration(fallbackModel: nil)

        _ = try await makeClient(transport: transport, recorder: recorder, configuration: noFallback)
            .analyze(transcript: "Hi.")

        let delays = await recorder.delays
        #expect(delays == [4])
    }

    @Test("A 5xx is retried")
    func retriesServerError() async throws {
        let transport = StubTransport([.response(Fixture.failure(500)), .response(Fixture.successAnalysis())])
        let recorder = DelayRecorder()

        _ = try await makeClient(transport: transport, recorder: recorder).analyze(transcript: "Hi.")

        let callCount = await transport.callCount
        let delays = await recorder.delays
        #expect(callCount == 2)
        #expect(delays == [2])
    }

    @Test("Persistent 429s exhaust three retries and surface rateLimited with Gemini's message")
    func exhaustsRetries() async throws {
        let transport = StubTransport(repeating: Fixture.failure(429), times: 4)
        let recorder = DelayRecorder()
        let client = makeClient(transport: transport, recorder: recorder)

        await #expect(throws: GeminiError.rateLimited(retryAfter: nil, message: "boom")) {
            try await client.analyze(transcript: "Hi.")
        }

        let callCount = await transport.callCount
        let delays = await recorder.delays
        #expect(callCount == 4)  // initial attempt + 3 retries
        #expect(delays == [2, 8, 30])
    }

    @Test("Per-minute 429s wait out the body's RetryInfo delay, then surface Gemini's message")
    func perMinuteQuotaUsesRetryInfo() async throws {
        let message = "Quota exceeded for metric: generate_content_free_tier_requests, limit: 10, model: gemini-3.8-flash"
        let response = Fixture.quotaFailure(message: message, quotaId: Fixture.perMinuteQuota, quotaValue: "10")
        let transport = StubTransport(repeating: response, times: 4)
        let recorder = DelayRecorder()
        let client = makeClient(transport: transport, recorder: recorder)

        await #expect(throws: GeminiError.rateLimited(retryAfter: 17.5, message: message)) {
            try await client.analyze(transcript: "Hi.")
        }

        let callCount = await transport.callCount
        let delays = await recorder.delays
        #expect(callCount == 4)
        #expect(delays == [17.5, 17.5, 17.5])
    }

    @Test("A Retry-After header wins over the body's RetryInfo delay")
    func retryAfterHeaderWinsOverBody() async throws {
        let transport = StubTransport([
            .response(Fixture.quotaFailure(message: "slow down", quotaId: Fixture.perMinuteQuota, headers: ["Retry-After": "7"])),
            .response(Fixture.successAnalysis()),
        ])
        let recorder = DelayRecorder()

        _ = try await makeClient(transport: transport, recorder: recorder).analyze(transcript: "Hi.")

        let delays = await recorder.delays
        #expect(delays == [7])
    }

    @Test("A 429 on a per-day quota fails at once with Gemini's message")
    func dailyQuotaFailsFast() async throws {
        let message = "You exceeded your current quota. Quota exceeded for metric: generate_content_free_tier_requests, limit: 50"
        let transport = StubTransport([
            .response(Fixture.quotaFailure(message: message, quotaId: "GenerateRequestsPerDayPerProjectPerModel-FreeTier", quotaValue: "50")),
        ])
        let recorder = DelayRecorder()
        let client = makeClient(transport: transport, recorder: recorder)

        await #expect(throws: GeminiError.quotaExhausted(message: message)) {
            try await client.analyze(transcript: "Hi.")
        }

        let callCount = await transport.callCount
        let delays = await recorder.delays
        #expect(callCount == 1)
        #expect(delays.isEmpty)
    }

    @Test("A 429 on a quota whose limit is 0 fails at once")
    func zeroLimitFailsFast() async throws {
        // Google says so in the message, the QuotaFailure's quotaValue, or both.
        let cases: [(message: String, quotaValue: String?)] = [
            ("Quota exceeded for metric: generate_content_free_tier_requests, limit: 0, model: gemini-3.1-pro", nil),
            ("Quota exceeded.", "0"),
        ]

        for (message, quotaValue) in cases {
            let response = Fixture.quotaFailure(message: message, quotaId: Fixture.perMinuteQuota, quotaValue: quotaValue)
            let transport = StubTransport([.response(response)])
            let recorder = DelayRecorder()
            let client = makeClient(transport: transport, recorder: recorder)

            await #expect(throws: GeminiError.quotaExhausted(message: message)) {
                try await client.analyze(transcript: "Hi.")
            }

            let callCount = await transport.callCount
            let delays = await recorder.delays
            #expect(callCount == 1)
            #expect(delays.isEmpty)
        }
    }

    @Test("Quota and key errors say where to fix them, and keep Gemini's message")
    func quotaCopy() {
        let quota = GeminiError.quotaExhausted(message: "Quota exceeded, limit: 0.").localizedDescription
        #expect(quota.contains("tomorrow"))
        #expect(quota.contains("… menu → AI"))
        #expect(quota.hasSuffix("Quota exceeded, limit: 0."))

        let limited = GeminiError.rateLimited(retryAfter: 17.5, message: "Please retry in 17.5s.").localizedDescription
        #expect(limited.hasSuffix("Please retry in 17.5s."))

        #expect(GeminiError.missingAPIKey.localizedDescription.contains("… menu → AI"))
    }

    @Test("Persistent 5xx surfaces the server error with its message")
    func exhaustsRetriesOnServerError() async throws {
        let transport = StubTransport(repeating: Fixture.failure(503, message: "overloaded"), times: 4)
        let client = makeClient(transport: transport, configuration: .init(fallbackModel: nil))

        await #expect(throws: GeminiError.server(status: 503, message: "overloaded")) {
            try await client.analyze(transcript: "Hi.")
        }

        let callCount = await transport.callCount
        #expect(callCount == 4)
    }

    // MARK: - Overload fallback

    @Test("A 503 switches to the fallback model at once, without waiting")
    func fallsBackOn503() async throws {
        let transport = StubTransport([.response(Fixture.failure(503)), .response(Fixture.successAnalysis())])
        let recorder = DelayRecorder()

        let analysis = try await makeClient(transport: transport, recorder: recorder).analyze(transcript: "Hi.")
        #expect(analysis == Fixture.analysis)

        let received = await transport.received
        let delays = await recorder.delays
        #expect(received.count == 2)
        #expect(received[0].url.absoluteString.hasSuffix("/models/gemini-3.8-flash:generateContent"))
        #expect(received[1].url.absoluteString.hasSuffix("/models/gemini-3.5-flash:generateContent"))
        #expect(delays.isEmpty)
    }

    @Test("The fallback model keeps the normal retry schedule and surfaces its own error")
    func fallbackRetriesThenFails() async throws {
        let transport = StubTransport(repeating: Fixture.failure(503, message: "overloaded"), times: 5)
        let recorder = DelayRecorder()
        let client = makeClient(transport: transport, recorder: recorder)

        await #expect(throws: GeminiError.server(status: 503, message: "overloaded")) {
            try await client.analyze(transcript: "Hi.")
        }

        let received = await transport.received
        let delays = await recorder.delays
        #expect(received.count == 5)  // primary once, then fallback + 3 retries
        #expect(received.dropFirst().allSatisfy { $0.url.absoluteString.contains("/models/gemini-3.5-flash:") })
        #expect(delays == [2, 8, 30])
    }

    @Test("Other 5xx retry on the same model instead of falling back")
    func nonOverloadServerErrorStaysOnModel() async throws {
        let transport = StubTransport([.response(Fixture.failure(500)), .response(Fixture.successAnalysis())])
        _ = try await makeClient(transport: transport).analyze(transcript: "Hi.")

        let received = await transport.received
        #expect(received.allSatisfy { $0.url.absoluteString.contains("/models/gemini-3.8-flash:") })
    }

    @Test("No fallback when the configured model already is the fallback")
    func noFallbackToSelf() async throws {
        let transport = StubTransport([.response(Fixture.failure(503)), .response(Fixture.successAnalysis())])
        let recorder = DelayRecorder()
        let configuration = GeminiClient.Configuration(model: "gemini-3.5-flash")

        _ = try await makeClient(transport: transport, recorder: recorder, configuration: configuration)
            .analyze(transcript: "Hi.")

        let delays = await recorder.delays
        #expect(delays == [2])  // retried with backoff, not fast-failed
    }

    @Test("Quizzes fall back too")
    func quizFallsBackOn503() async throws {
        let quizJSON = #"{"title":"T","questions":[{"prompt":"Q?","options":["a","b","c","d"],"answerIndex":1,"explanation":"b."}]}"#
        let transport = StubTransport([.response(Fixture.failure(503)), .response(Fixture.success(text: quizJSON))])

        let quiz = try await makeClient(transport: transport).generateQuiz(fromNotes: "Notes.")
        #expect(quiz.questions.count == 1)

        let received = await transport.received
        #expect(received[1].url.absoluteString.contains("/models/gemini-3.5-flash:"))
    }

    @Test("A 4xx is not retried and carries Gemini's message")
    func doesNotRetryClientError() async throws {
        let transport = StubTransport([.response(Fixture.failure(400, message: "API key not valid"))])
        let recorder = DelayRecorder()
        let client = makeClient(transport: transport, recorder: recorder)

        await #expect(throws: GeminiError.http(status: 400, message: "API key not valid")) {
            try await client.analyze(transcript: "Hi.")
        }

        let callCount = await transport.callCount
        let delays = await recorder.delays
        #expect(callCount == 1)
        #expect(delays.isEmpty)
    }

    @Test("A transport failure surfaces as .transport")
    func transportFailure() async throws {
        struct Offline: LocalizedError {
            var errorDescription: String? { "offline" }
        }
        let transport = StubTransport([.failure(Offline())])
        let client = makeClient(transport: transport)

        await #expect(throws: GeminiError.transport("offline")) {
            try await client.analyze(transcript: "Hi.")
        }
    }

    // MARK: - Response parsing

    @Test("Safety blocks surface as .blocked")
    func blockedPrompt() async throws {
        let transport = StubTransport([.response(Fixture.blocked())])
        let client = makeClient(transport: transport)

        await #expect(throws: GeminiError.blocked(reason: "SAFETY")) {
            try await client.analyze(transcript: "Hi.")
        }
    }

    @Test("A SAFETY finish reason surfaces as .blocked")
    func blockedCompletion() async throws {
        let transport = StubTransport([.response(Fixture.success(text: "{}", finishReason: "SAFETY"))])
        let client = makeClient(transport: transport)

        await #expect(throws: GeminiError.blocked(reason: "SAFETY")) {
            try await client.analyze(transcript: "Hi.")
        }
    }

    @Test("No candidates surfaces as .emptyResponse")
    func emptyCandidates() async throws {
        let transport = StubTransport([.response(Fixture.noCandidates)])
        let client = makeClient(transport: transport)

        await #expect(throws: GeminiError.emptyResponse) {
            try await client.analyze(transcript: "Hi.")
        }
    }

    @Test("Non-JSON candidate text surfaces as .malformedJSON")
    func malformedCandidateText() async throws {
        let transport = StubTransport([.response(Fixture.success(text: "Sorry, I cannot help."))])
        let client = makeClient(transport: transport)

        await #expect(throws: GeminiError.malformedJSON("Sorry, I cannot help.")) {
            try await client.analyze(transcript: "Hi.")
        }
    }

    @Test("JSON that does not match the schema surfaces as .malformedJSON")
    func offSchemaJSON() async throws {
        let text = #"{"summary":"ok"}"#  // missing the three required siblings
        let transport = StubTransport([.response(Fixture.success(text: text))])
        let client = makeClient(transport: transport)

        await #expect(throws: GeminiError.malformedJSON(text)) {
            try await client.analyze(transcript: "Hi.")
        }
    }

    @Test("A truncated completion surfaces as .malformedJSON, not a crash")
    func truncatedCompletion() async throws {
        let text = #"{"summary":"The team ag"#
        let transport = StubTransport([.response(Fixture.success(text: text, finishReason: "MAX_TOKENS"))])
        let client = makeClient(transport: transport)

        await #expect(throws: GeminiError.malformedJSON(text)) {
            try await client.analyze(transcript: "Hi.")
        }
    }

    @Test("Multi-part candidate text is joined before decoding")
    func joinsParts() throws {
        let json = String(data: try JSONEncoder().encode(Fixture.analysis), encoding: .utf8)!
        let split = json.index(json.startIndex, offsetBy: 20)

        let payload: [String: Any] = [
            "candidates": [[
                "content": ["parts": [["text": String(json[..<split])], ["text": String(json[split...])]]],
                "finishReason": "STOP",
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        #expect(try GeminiClient.decodeAnalysis(from: data) == Fixture.analysis)
    }
}

@Suite("Response schema")
struct GeminiSchemaTests {
    private var encoded: [String: Any] {
        let data = try! JSONEncoder().encode(GeminiSchema.meetingAnalysis)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test("The root object requires all four fields and pins their order")
    func rootShape() {
        #expect(encoded["type"] as? String == "OBJECT")
        #expect(encoded["required"] as? [String] == ["summary", "keyDecisions", "actionItems", "followUpEmail"])
        #expect(encoded["propertyOrdering"] as? [String] == ["summary", "keyDecisions", "actionItems", "followUpEmail"])
    }

    @Test("actionItems is an array of objects requiring task and owner")
    func actionItemShape() throws {
        let properties = try #require(encoded["properties"] as? [String: Any])
        let actionItems = try #require(properties["actionItems"] as? [String: Any])
        #expect(actionItems["type"] as? String == "ARRAY")

        let item = try #require(actionItems["items"] as? [String: Any])
        #expect(item["type"] as? String == "OBJECT")
        #expect(item["required"] as? [String] == ["task", "owner"])
        #expect(item["propertyOrdering"] as? [String] == ["task", "owner", "due"])
    }

    @Test("MeetingAnalysis round-trips through JSON")
    func roundTrip() throws {
        let data = try JSONEncoder().encode(Fixture.analysis)
        #expect(try JSONDecoder().decode(MeetingAnalysis.self, from: data) == Fixture.analysis)
    }
}

extension Fixture {
    static let perMinuteQuota = "GenerateRequestsPerMinutePerProjectPerModel-FreeTier"

    /// A 429 shaped like Gemini's: the reason is in `details` (a QuotaFailure naming the quota, a Help
    /// link, a RetryInfo with the wait), not in headers.
    static func quotaFailure(
        message: String,
        quotaId: String,
        quotaValue: String? = nil,
        retryDelay: String = "17.5s",
        headers: [String: String] = [:]
    ) -> HTTPResponse {
        var violation: [String: Any] = [
            "quotaMetric": "generativelanguage.googleapis.com/generate_content_free_tier_requests",
            "quotaId": quotaId,
            "quotaDimensions": ["location": "global", "model": "gemini-3.8-flash"],
        ]
        if let quotaValue { violation["quotaValue"] = quotaValue }

        let body: [String: Any] = ["error": [
            "code": 429,
            "message": message,
            "status": "RESOURCE_EXHAUSTED",
            "details": [
                ["@type": "type.googleapis.com/google.rpc.QuotaFailure", "violations": [violation]],
                ["@type": "type.googleapis.com/google.rpc.Help",
                 "links": [["description": "Learn more", "url": "https://ai.google.dev/gemini-api/docs/rate-limits"]]],
                ["@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": retryDelay],
            ],
        ]]
        return HTTPResponse(status: 429, headers: headers, body: try! JSONSerialization.data(withJSONObject: body))
    }
}
