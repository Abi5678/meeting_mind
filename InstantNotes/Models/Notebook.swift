//
//  Notebook.swift
//  Instant Notes
//
// A group of sources (imported documents, web pages, notes and recordings) that Quolio summarizes
// together and answers questions about. Synced with iCloud, so it keeps to the same CloudKit rules
// as Note: a default for every value, optional relationships with explicit inverses.

import Foundation
import SwiftData
import MeetingMindKit

@Model
final class Notebook {
    var id: UUID = UUID()
    var title: String = "Untitled notebook"
    var createdAt: Date = Date.now
    var modifiedAt: Date = Date.now
    /// The note holding the combined summary; nil until the notebook is first summarized. An id
    /// rather than a relationship, so deleting either leaves the other alone.
    var summaryNoteID: UUID? = nil
    /// The note holding the study guide; nil until one is written. An id, like `summaryNoteID`.
    var studyGuideNoteID: UUID? = nil
    /// JSON-encoded [SourceDigest]: what was read from each source, so only new and changed
    /// sources are read again.
    var digestsJSON: String = "[]"
    /// Notes are shared with the notes list and other notebooks; removing one from here keeps it.
    @Relationship(inverse: \Note.notebooks) var sources: [Note]? = []
    @Relationship(deleteRule: .cascade, inverse: \NotebookChatMessage.notebook) var chatMessages: [NotebookChatMessage]? = []

    init(title: String) {
        self.title = title
    }

    var digests: [SourceDigest] {
        get { (try? JSONDecoder().decode([SourceDigest].self, from: Data(digestsJSON.utf8))) ?? [] }
        set { digestsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    }

    /// Sources in title order, the order the summary numbers them.
    var orderedSources: [Note] {
        (sources ?? []).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Digests of the current sources that still match them, keyed by note.
    var currentDigests: [UUID: SourceDigest] {
        let digests = Dictionary(digests.map { ($0.noteID, $0) }, uniquingKeysWith: { first, _ in first })
        return Dictionary(uniqueKeysWithValues: (sources ?? []).compactMap { note in
            digests[note.id].flatMap { $0.sourceModifiedAt == note.modifiedAt ? (note.id, $0) : nil }
        })
    }

    /// Whether the summary misses a source, still has a removed one, or read one before it changed.
    var summaryIsStale: Bool {
        let sources = sources ?? []
        return summaryNoteID == nil || digests.count != sources.count || currentDigests.count != sources.count
    }

    /// What a quiz, flashcards or study guide reads: every source, with what the summary took from it.
    var studyMaterial: String {
        let digests = currentDigests
        return NotebookStudy.material(orderedSources.map { (title: $0.title, digest: digests[$0.id], text: $0.sourceText) })
    }
}

/// One turn of "Ask this notebook". Kept with the notebook, so the conversation is there next time.
@Model
final class NotebookChatMessage {
    var id: UUID = UUID()
    var role: String = "user" // "user" or "assistant"
    var content: String = ""
    var createdAt: Date = Date.now
    /// JSON-encoded [NotebookChat.Source] an answer was written from, so its [n] links still open
    /// the right note later.
    var sourcesJSON: String = "[]"
    var notebook: Notebook?

    init(role: String, content: String, sources: [NotebookChat.Source] = []) {
        self.role = role
        self.content = content
        self.createdAt = .now
        self.sources = sources
    }

    var sources: [NotebookChat.Source] {
        get { (try? JSONDecoder().decode([NotebookChat.Source].self, from: Data(sourcesJSON.utf8))) ?? [] }
        set { sourcesJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    }
}

extension Note {
    /// Everything a notebook reads from this note: its text, then the words in its ink and photos.
    var sourceText: String {
        let photos = (images ?? []).compactMap(\.recognizedText).filter { !$0.isEmpty }
        return ([blockDocument.plainText, inkText ?? ""] + photos)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
