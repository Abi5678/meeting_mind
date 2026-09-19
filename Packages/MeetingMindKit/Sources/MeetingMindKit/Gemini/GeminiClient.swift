import Foundation

public struct GeminiClient: Sendable {
    /// Injected so retry tests do not actually wait 2s/8s/30s.
    public typealias Sleep = @Sendable (TimeInterval) async throws -> Void

    public struct Configuration: Sendable {
        public var model: String
        /// Where a 503 (model overloaded) on `model` goes instead of waiting out the backoff.
        /// Points at an older Flash generation so the two don't shed load together; nil turns the switch off.
        public var fallbackModel: String?
        public var baseURL: URL
        /// Retries *after* the initial attempt, so worst case is `1 + maxRetries` requests.
        public var maxRetries: Int
        public var backoff: [TimeInterval]
        /// A 90-minute transcript is ~20k tokens and fits Flash's context in one call. This
        /// bound only exists to stop a pathological transcript from being sent at all.
        public var maxTranscriptCharacters: Int
        public var temperature: Double

        public init(
            model: String = "gemini-3.8-flash",
            fallbackModel: String? = "gemini-3.5-flash",
            baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
            maxRetries: Int = 3,
            backoff: [TimeInterval] = [2, 8, 30],
            maxTranscriptCharacters: Int = 300_000,
            temperature: Double = 0.2
        ) {
            self.model = model
            self.fallbackModel = fallbackModel
            self.baseURL = baseURL
            self.maxRetries = maxRetries
            self.backoff = backoff
            self.maxTranscriptCharacters = maxTranscriptCharacters
            self.temperature = temperature
        }
    }

    private let apiKey: String
    private let configuration: Configuration
    private let transport: any HTTPTransport
    private let sleep: Sleep

    public init(
        apiKey: String,
        configuration: Configuration = Configuration(),
        transport: any HTTPTransport = URLSessionTransport(),
        sleep: @escaping Sleep = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.apiKey = apiKey
        self.configuration = configuration
        self.transport = transport
        self.sleep = sleep
    }

    public func analyze(transcript: String) async throws -> MeetingAnalysis {
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeminiError.emptyTranscript }

        let bounded = String(trimmed.prefix(configuration.maxTranscriptCharacters))
        let response = try await send(
            prompt: PromptBuilder.analysisPrompt(transcript: bounded),
            schema: GeminiSchema.meetingAnalysis
        )
        return try Self.decodeAnalysis(from: response.body)
    }

    /// Writes a multiple-choice quiz grounded in `notes`. Questions the model could not make
    /// gradeable (answer index outside the options) are dropped rather than shown broken.
    public func generateQuiz(fromNotes notes: String, questionCount: Int = 5) async throws -> Quiz {
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }

        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeminiError.emptyNotes }

        let bounded = String(trimmed.prefix(configuration.maxTranscriptCharacters))
        let response = try await send(
            prompt: PromptBuilder.quizPrompt(notes: bounded, questionCount: questionCount),
            schema: GeminiSchema.quiz
        )
        let (quiz, text) = try Self.decode(Quiz.self, from: response.body)

        let playable = quiz.questions.filter(\.isPlayable)
        guard !playable.isEmpty else { throw GeminiError.malformedJSON(text) }
        return Quiz(title: quiz.title, questions: playable)
    }

    /// Suggests up to five topic tags for a note. `existingTags` are the user's tags on other
    /// notes; the model is told to reuse them, so one topic does not end up tagged three ways.
    public func suggestTags(title: String, notes: String, existingTags: [String] = []) async throws -> [String] {
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }

        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeminiError.emptyNotes }

        let bounded = String(trimmed.prefix(configuration.maxTranscriptCharacters))
        let response = try await send(
            prompt: PromptBuilder.tagPrompt(title: title, notes: bounded, existingTags: existingTags),
            schema: GeminiSchema.tags
        )
        return Self.normalizedTags(try Self.decode(TagSuggestion.self, from: response.body).value.tags)
    }

    /// Lowercased, `#` stripped, duplicates dropped, at most five.
    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        let cleaned = tags.compactMap { raw -> String? in
            let tag = raw.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines)).lowercased()
            guard !tag.isEmpty, seen.insert(tag).inserted else { return nil }
            return tag
        }
        return Array(cleaned.prefix(5))
    }

    // MARK: - Request

    func makeRequest(
        prompt: String,
        schema: Schema = GeminiSchema.meetingAnalysis,
        model: String? = nil
    ) throws -> HTTPRequest {
        let endpoint = "\(configuration.baseURL.absoluteString)/models/\(model ?? configuration.model):generateContent"
        guard let url = URL(string: endpoint) else {
            throw GeminiError.transport("Invalid endpoint: \(endpoint)")
        }

        let body = GenerateContentRequest(
            prompt: prompt,
            schema: schema,
            temperature: configuration.temperature
        )

        return HTTPRequest(
            url: url,
            method: "POST",
            headers: [
                "x-goog-api-key": apiKey,
                "Content-Type": "application/json",
            ],
            body: try JSONEncoder().encode(body)
        )
    }

    // MARK: - Retry

    /// A 503 on the configured model skips its backoff and goes to `fallbackModel`, which then
    /// gets the normal retry schedule. Every other status is handled by `sendWithRetry` alone.
    private func send(prompt: String, schema: Schema) async throws -> HTTPResponse {
        guard let fallback = configuration.fallbackModel, fallback != configuration.model else {
            return try await sendWithRetry(makeRequest(prompt: prompt, schema: schema))
        }
        do {
            return try await sendWithRetry(makeRequest(prompt: prompt, schema: schema), failFastOn503: true)
        } catch GeminiError.server(status: 503, _) {
            return try await sendWithRetry(makeRequest(prompt: prompt, schema: schema, model: fallback))
        }
    }

    private func sendWithRetry(_ request: HTTPRequest, failFastOn503: Bool = false) async throws -> HTTPResponse {
        var attempt = 0
        while true {
            let response: HTTPResponse
            do {
                response = try await transport.send(request)
            } catch let error as GeminiError {
                throw error
            } catch {
                throw GeminiError.transport(error.localizedDescription)
            }

            if (200..<300).contains(response.status) { return response }

            let isRetryable = response.status == 429 || (500..<600).contains(response.status)
            let hasFallback = failFastOn503 && response.status == 503
            guard isRetryable, !hasFallback, attempt < configuration.maxRetries else {
                throw Self.error(for: response)
            }

            try await sleep(Self.retryAfter(response) ?? backoffDelay(forAttempt: attempt))
            attempt += 1
        }
    }

    private func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        guard let last = configuration.backoff.last else { return 0 }
        return attempt < configuration.backoff.count ? configuration.backoff[attempt] : last
    }

    /// Google sends `Retry-After` as whole seconds on 429.
    private static func retryAfter(_ response: HTTPResponse) -> TimeInterval? {
        guard let value = response.header("Retry-After"), let seconds = TimeInterval(value), seconds >= 0 else {
            return nil
        }
        return seconds
    }

    private static func error(for response: HTTPResponse) -> GeminiError {
        let message = (try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: response.body))?.error.message
            ?? String(data: response.body, encoding: .utf8)
            ?? ""

        return switch response.status {
        case 429: .rateLimited(retryAfter: retryAfter(response))
        case 500..<600: .server(status: response.status, message: message)
        default: .http(status: response.status, message: message)
        }
    }

    // MARK: - Decoding

    static func decodeAnalysis(from data: Data) throws -> MeetingAnalysis {
        try decode(MeetingAnalysis.self, from: data).value
    }

    /// Unwraps the candidate text and decodes it as `T`. Also returns the raw text, for error reporting.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> (value: T, text: String) {
        guard let envelope = try? JSONDecoder().decode(GenerateContentResponse.self, from: data) else {
            throw GeminiError.malformedJSON(String(data: data, encoding: .utf8) ?? "<non-UTF8>")
        }

        if let blockReason = envelope.promptFeedback?.blockReason {
            throw GeminiError.blocked(reason: blockReason)
        }

        guard let candidate = envelope.candidates?.first else {
            throw GeminiError.emptyResponse
        }

        if let reason = candidate.finishReason, reason == "SAFETY" || reason == "PROHIBITED_CONTENT" {
            throw GeminiError.blocked(reason: reason)
        }

        // A truncated completion (finishReason == MAX_TOKENS) lands in `malformedJSON` below,
        // which is the right surface: the JSON really is unparseable.
        let text = (candidate.content?.parts ?? []).compactMap(\.text).joined()
        guard !text.isEmpty else { throw GeminiError.emptyResponse }

        guard let json = text.data(using: .utf8) else {
            throw GeminiError.malformedJSON(text)
        }

        do {
            return (try JSONDecoder().decode(T.self, from: json), text)
        } catch {
            throw GeminiError.malformedJSON(text)
        }
    }
}
