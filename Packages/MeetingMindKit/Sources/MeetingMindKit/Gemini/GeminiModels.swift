import Foundation

// MARK: - Response schema

/// The subset of Gemini's OpenAPI-flavoured schema language that `MeetingAnalysis` and `Quiz` need.
///
/// Gemini constrains generation to this schema when it is sent as `responseSchema`
/// alongside `responseMimeType: "application/json"`.
indirect enum Schema: Encodable, Sendable {
    case string(description: String)
    case integer(description: String)
    case array(of: Schema, description: String)
    case object(properties: [(name: String, schema: Schema)], required: [String], description: String?)

    private enum Key: String, CodingKey {
        case type, description, properties, required, items, propertyOrdering
    }

    private struct PropertyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case let .string(description):
            try container.encode("STRING", forKey: .type)
            try container.encode(description, forKey: .description)

        case let .integer(description):
            try container.encode("INTEGER", forKey: .type)
            try container.encode(description, forKey: .description)

        case let .array(element, description):
            try container.encode("ARRAY", forKey: .type)
            try container.encode(description, forKey: .description)
            try container.encode(element, forKey: .items)

        case let .object(properties, required, description):
            try container.encode("OBJECT", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            var propertyContainer = container.nestedContainer(keyedBy: PropertyKey.self, forKey: .properties)
            for property in properties {
                try propertyContainer.encode(property.schema, forKey: PropertyKey(property.name))
            }
            try container.encode(required, forKey: .required)
            // Without propertyOrdering the model may emit keys in an arbitrary order,
            // which measurably degrades output quality on nested objects.
            try container.encode(properties.map(\.name), forKey: .propertyOrdering)
        }
    }
}

enum GeminiSchema {
    static let meetingAnalysis: Schema = .object(
        properties: [
            (
                "summary",
                .string(description: "A 3-6 sentence prose summary of what the meeting covered and concluded.")
            ),
            (
                "keyDecisions",
                .array(
                    of: .string(description: "One decision, stated as a complete sentence."),
                    description: "Decisions the participants actually agreed on. Empty if none were reached."
                )
            ),
            (
                "actionItems",
                .array(
                    of: .object(
                        properties: [
                            ("task", .string(description: "The work to be done, in the imperative.")),
                            ("owner", .string(description: "Who owns it, or \"Unassigned\" if the transcript names nobody.")),
                            ("due", .string(description: "The deadline exactly as spoken, e.g. \"Friday\". Omit if none was stated.")),
                        ],
                        required: ["task", "owner"],
                        description: nil
                    ),
                    description: "Concrete follow-up tasks committed to during the meeting."
                )
            ),
            (
                "followUpEmail",
                .object(
                    properties: [
                        ("subject", .string(description: "A concise subject line for the recap email.")),
                        ("body", .string(description: "The recap email body, in plain text with newlines.")),
                    ],
                    required: ["subject", "body"],
                    description: "A ready-to-send recap email addressed to the participants."
                )
            ),
        ],
        required: ["summary", "keyDecisions", "actionItems", "followUpEmail"],
        description: nil
    )

    static let quiz: Schema = .object(
        properties: [
            ("title", .string(description: "A short, playful quiz title about the notes' topic, at most 6 words.")),
            (
                "questions",
                .array(
                    of: .object(
                        properties: [
                            ("prompt", .string(description: "The question, answerable from the notes alone.")),
                            (
                                "options",
                                .array(
                                    of: .string(description: "One answer choice, at most 12 words."),
                                    description: "Exactly 4 answer choices: one correct, three plausible but wrong."
                                )
                            ),
                            ("answerIndex", .integer(description: "Zero-based index of the correct choice in options.")),
                            ("explanation", .string(description: "One short sentence on why the correct choice is right. Shown after right and wrong answers alike, so no praise.")),
                        ],
                        required: ["prompt", "options", "answerIndex", "explanation"],
                        description: nil
                    ),
                    description: "The quiz questions."
                )
            ),
        ],
        required: ["title", "questions"],
        description: nil
    )
}

// MARK: - Request

struct GenerateContentRequest: Encodable {
    struct Content: Encodable {
        let parts: [Part]
    }

    struct Part: Encodable {
        let text: String
    }

    struct GenerationConfig: Encodable {
        let responseMimeType: String
        let responseSchema: Schema
        let temperature: Double
    }

    let contents: [Content]
    let generationConfig: GenerationConfig

    init(prompt: String, schema: Schema, temperature: Double) {
        contents = [Content(parts: [Part(text: prompt)])]
        generationConfig = GenerationConfig(
            responseMimeType: "application/json",
            responseSchema: schema,
            temperature: temperature
        )
    }
}

// MARK: - Response

struct GenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }
            let parts: [Part]?
        }
        let content: Content?
        let finishReason: String?
    }

    struct PromptFeedback: Decodable {
        let blockReason: String?
    }

    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
}

/// Gemini's error envelope, e.g. `{"error": {"code": 429, "message": "...", "status": "RESOURCE_EXHAUSTED"}}`
struct GeminiErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let code: Int
        let message: String
        let status: String?
    }
    let error: APIError
}

// MARK: - Errors

public enum GeminiError: Error, Equatable, Sendable {
    /// No API key has been saved in Settings.
    case missingAPIKey
    case emptyTranscript
    /// There is no note text to write a quiz from.
    case emptyNotes
    /// 429, after retries were exhausted.
    case rateLimited(retryAfter: TimeInterval?)
    /// 5xx, after retries were exhausted.
    case server(status: Int, message: String)
    /// A non-retryable non-2xx: bad key (401/403), bad request (400), unknown model (404).
    case http(status: Int, message: String)
    /// Safety filters rejected the prompt or the completion.
    case blocked(reason: String)
    /// 2xx with no usable candidate text.
    case emptyResponse
    /// The model returned text that does not decode as the requested type (`MeetingAnalysis`, `Quiz`).
    case malformedJSON(String)
    case transport(String)
}

extension GeminiError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No Gemini API key. Add one in Settings."
        case .emptyTranscript:
            "There is no transcript to analyse yet."
        case .emptyNotes:
            "Write a few notes first, then make a quiz."
        case let .rateLimited(retryAfter):
            if let retryAfter {
                "Gemini is rate limiting this key. Try again in \(Int(retryAfter.rounded()))s."
            } else {
                "Gemini is rate limiting this key. Try again shortly."
            }
        case let .server(status, message):
            "Gemini is having trouble (HTTP \(status)). \(message)"
        case let .http(status, message):
            "Gemini rejected the request (HTTP \(status)). \(message)"
        case let .blocked(reason):
            "Gemini blocked this transcript (\(reason))."
        case .emptyResponse:
            "Gemini returned an empty response."
        case .malformedJSON:
            "Gemini returned a response that could not be read."
        case let .transport(message):
            "Could not reach Gemini. \(message)"
        }
    }
}
