//
//  AIService.swift
//  Instant Notes
//
// Orchestrates AI operations with queueing and throttling.
/// Respects Gemini free tier limits (~10-15 req/min).

import Foundation
import MeetingMindKit

@MainActor
final class AIService {
    static let shared = AIService()

    private var requestCountPerMinute: Int = 0
    private var lastMinuteReset: Date = .now

    /// Suggest tags for a note from its text, reusing `existingTags` (the user's other tags) where they fit.
    func suggestTags(for title: String, notes: String, existingTags: [String]) async throws -> [String] {
        guard let key = GeminiKey.current else { throw GeminiError.missingAPIKey }
        let model = UserDefaults.standard.string(forKey: "gemini_model") ?? "gemini-3.8-flash"
        return try await GeminiClient(apiKey: key, configuration: .init(model: model))
            .suggestTags(title: title, notes: notes, existingTags: existingTags)
    }

    /// Auto-organize a note: summarize + suggest tags.
    func organize(title: String, content: String) async -> OrganizeResult? {
        guard hasAPIKey else { return nil }

        // Stub: no summarize call in GeminiClient yet.
        let summary: String? = nil
        let tags = (try? await suggestTags(for: title, notes: content, existingTags: [])) ?? []

        return .init(summary: summary, suggestedTags: tags)
    }

    /// Find related notes using on-device sentence embeddings (NLEmbedding).
    func findRelatedNotes(for note: Note, allNotes: [Note]) async -> [Note] {
        // Stub: in production this would use NLEmbedding for semantic similarity.
        // For now, keyword matching fallback.
        let words = Set(note.title.lowercased().split(separator: " ").map(String.init))
        return allNotes.filter { n in
            guard n.id != note.id else { return false }
            let summary = n.summary?.lowercased() ?? ""
            return n.tags.contains(where: { words.contains($0.lowercased()) }) ||
                   words.contains(where: { summary.contains($0) })
        }.prefix(5).map { $0 }
    }

    /// Schedule a task in the throttled queue. The task will execute when capacity is available.
    func scheduleTask(_ task: @escaping () async throws -> Void) async -> UUID {
        let id = UUID()
        pendingTasks[id] = task

        // Trigger processing if not already running
        Task {
            await processNextTask()
        }

        return id
    }

    // MARK: - Private

    private var pendingTasks: [UUID: () async throws -> Void] = [:]

    private func throttleCheck() -> Bool {
        if Date().timeIntervalSince(lastMinuteReset) >= 60 {
            requestCountPerMinute = 0
            lastMinuteReset = .now
        }
        return requestCountPerMinute < 12 // safety margin below free tier limit
    }

    private func rateLimitBackoff() async {
        try? await Task.sleep(nanoseconds: 5_000_000_000) // wait 5 seconds
    }

    var hasAPIKey: Bool {
        let keychain = KeychainHelper()
        return keychain.getString(forKey: "gemini_api_key") != nil
    }

    private func processNextTask() async {
        guard throttleCheck() else {
            await rateLimitBackoff()
            return
        }

        guard let (id, task) = pendingTasks.first else { return }
        pendingTasks.removeValue(forKey: id)
        requestCountPerMinute += 1

        try? await task()
    }
}

struct OrganizeResult: Codable {
    let summary: String?
    let suggestedTags: [String]
}
