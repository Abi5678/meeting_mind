import Foundation

@testable import MeetingMindKit

/// Serves a scripted sequence of responses and records what it was asked for.
actor StubTransport: HTTPTransport {
    enum Step {
        case response(HTTPResponse)
        case failure(any Error)
    }

    struct Exhausted: Error {}

    private var steps: [Step]
    private(set) var received: [HTTPRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    init(repeating response: HTTPResponse, times: Int) {
        steps = Array(repeating: .response(response), count: times)
    }

    var callCount: Int { received.count }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        received.append(request)
        guard !steps.isEmpty else { throw Exhausted() }

        switch steps.removeFirst() {
        case let .response(response): return response
        case let .failure(error): throw error
        }
    }
}

actor DelayRecorder {
    private(set) var delays: [TimeInterval] = []

    func record(_ delay: TimeInterval) {
        delays.append(delay)
    }

    /// Drop-in for `GeminiClient.Sleep` that returns immediately.
    nonisolated var sleep: GeminiClient.Sleep {
        { await self.record($0) }
    }
}

// MARK: - Wire fixtures

/// Mirrors Gemini's success envelope so the inner JSON gets escaped correctly.
private struct WireResponse: Encodable {
    struct Candidate: Encodable {
        struct Content: Encodable {
            struct Part: Encodable { let text: String }
            let parts: [Part]
        }
        let content: Content
        let finishReason: String
    }
    let candidates: [Candidate]
}

enum Fixture {
    static let analysis = MeetingAnalysis(
        summary: "The team locked MVP scope and cut Notion sync.",
        keyDecisions: ["Ship without Notion integration.", "Default model is base.en-q5_1."],
        actionItems: [
            .init(task: "Wireframe the model download flow", owner: "Priya", due: "Fri"),
            .init(task: "Benchmark small.en on older devices", owner: "Unassigned"),
        ],
        followUpEmail: .init(subject: "Recap — kickoff", body: "Hi all,\n\nScope is locked.\n\n— Abishek")
    )

    /// A 200 whose candidate text is `text` verbatim.
    static func success(text: String, finishReason: String = "STOP") -> HTTPResponse {
        let wire = WireResponse(candidates: [
            .init(content: .init(parts: [.init(text: text)]), finishReason: finishReason)
        ])
        return HTTPResponse(status: 200, body: try! JSONEncoder().encode(wire))
    }

    /// A 200 whose candidate text is `Fixture.analysis` encoded as JSON.
    static func successAnalysis() -> HTTPResponse {
        let json = String(data: try! JSONEncoder().encode(analysis), encoding: .utf8)!
        return success(text: json)
    }

    static func failure(_ status: Int, message: String = "boom", headers: [String: String] = [:]) -> HTTPResponse {
        let body = #"{"error":{"code":\#(status),"message":"\#(message)","status":"ERROR"}}"#
        return HTTPResponse(status: status, headers: headers, body: Data(body.utf8))
    }

    static func blocked(reason: String = "SAFETY") -> HTTPResponse {
        HTTPResponse(status: 200, body: Data(#"{"promptFeedback":{"blockReason":"\#(reason)"}}"#.utf8))
    }

    static let noCandidates = HTTPResponse(status: 200, body: Data(#"{"candidates":[]}"#.utf8))
}

// MARK: - Request introspection

extension HTTPRequest {
    var jsonBody: [String: Any] {
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return [:]
        }
        return object
    }

    /// The single text part the client sends.
    var promptText: String {
        let contents = jsonBody["contents"] as? [[String: Any]] ?? []
        let parts = contents.first?["parts"] as? [[String: Any]] ?? []
        return parts.first?["text"] as? String ?? ""
    }

    var generationConfig: [String: Any] {
        jsonBody["generationConfig"] as? [String: Any] ?? [:]
    }
}
