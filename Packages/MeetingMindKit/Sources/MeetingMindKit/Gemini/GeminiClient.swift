import Foundation

public struct GeminiClient: Sendable {
    /// Injected so retry tests do not actually wait 2s/8s/30s.
    public typealias Sleep = @Sendable (TimeInterval) async throws -> Void

    public struct Configuration: Sendable {
        public var model: String
        public var baseURL: URL
        /// Retries *after* the initial attempt, so worst case is `1 + maxRetries` requests.
        public var maxRetries: Int
        public var backoff: [TimeInterval]
        /// A 90-minute transcript is ~20k tokens and fits Flash's context in one call. This
        /// bound only exists to stop a pathological transcript from being sent at all.
        public var maxTranscriptCharacters: Int
        public var temperature: Double

        public init(
            model: String = "gemini-3-flash-preview",
            baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
            maxRetries: Int = 3,
            backoff: [TimeInterval] = [2, 8, 30],
            maxTranscriptCharacters: Int = 300_000,
            temperature: Double = 0.2
        ) {
            self.model = model
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
        let request = try makeRequest(prompt: PromptBuilder.analysisPrompt(transcript: bounded))
        let response = try await sendWithRetry(request)
        return try Self.decodeAnalysis(from: response.body)
    }

    // MARK: - Request

    func makeRequest(prompt: String) throws -> HTTPRequest {
        let endpoint = "\(configuration.baseURL.absoluteString)/models/\(configuration.model):generateContent"
        guard let url = URL(string: endpoint) else {
            throw GeminiError.transport("Invalid endpoint: \(endpoint)")
        }

        let body = GenerateContentRequest(
            prompt: prompt,
            schema: GeminiSchema.meetingAnalysis,
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

    private func sendWithRetry(_ request: HTTPRequest) async throws -> HTTPResponse {
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
            guard isRetryable, attempt < configuration.maxRetries else {
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
            return try JSONDecoder().decode(MeetingAnalysis.self, from: json)
        } catch {
            throw GeminiError.malformedJSON(text)
        }
    }
}
