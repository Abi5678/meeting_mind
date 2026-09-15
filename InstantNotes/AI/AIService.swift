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

    /// Suggest tags for a note based on its content.
    func suggestTags(for title: String, summary: String?, context: [String]) async -> [String] {
        guard hasAPIKey else { return [] }

        let prompt = PromptBuilder.buildTagPrompt(
            noteTitle: title,
            noteSummary: summary ?? "",
            relatedNoteTitles: context
        )

        // Stub: MeetingMindKit's GeminiClient only exposes `analyze(transcript:)` today — there is
        // no free-form chat call to send `prompt` to yet. Wire it here, then feed `parseTags(from:)`.
        _ = prompt
        return []
    }

    /// Auto-organize a note: summarize + suggest tags.
    func organize(title: String, content: String) async -> OrganizeResult? {
        guard hasAPIKey else { return nil }

        // Stub: no summarize call in GeminiClient yet (see suggestTags).
        let summary: String? = nil
        let tags = await suggestTags(for: title, summary: nil, context: [])

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

    private func parseTags(from text: String) -> [String] {
        // Simple tag parsing: split by comma, filter empty
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 1 }
            .prefix(10) // limit to 10 tags max
            .map { String($0) }
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

// MARK: - PromptBuilder helper (reuse from MeetingMindKit)

extension PromptBuilder {
    static func buildTagPrompt(noteTitle: String, noteSummary: String, relatedNoteTitles: [String]) -> String {
        var prompt = "Suggest up to 10 tags for a note with this title and summary:\n\n"
        prompt += "Title: \(noteTitle)\n"
        prompt += "Summary: \(noteSummary)\n\n"

        if !relatedNoteTitles.isEmpty {
            prompt += "Related notes:\n\(relatedNoteTitles.prefix(5).joined(separator: "\n"))\n\n"
        }

        prompt += "Return tags as a comma-separated list. No markdown formatting."
        return prompt
    }
}
