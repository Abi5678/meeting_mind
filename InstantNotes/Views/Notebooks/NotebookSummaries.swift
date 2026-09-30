//
//  NotebookSummaries.swift
//  Instant Notes
//
// Summarizes notebooks with Apple's on-device model: a digest of each new or changed source, then
// an overview of them all, written into the notebook's summary note. Shared across the app, so a
// summary keeps going when you leave the notebook.

import Foundation
import SwiftData
import MeetingMindKit

@MainActor
@Observable
final class NotebookSummaries {
    static let shared = NotebookSummaries()

    /// What each running summary is doing, by notebook, in words for the user.
    private(set) var progress: [UUID: String] = [:]
    /// Why the last summary of a notebook failed.
    private(set) var errors: [UUID: String] = [:]

    func isRunning(_ notebook: Notebook) -> Bool { progress[notebook.id] != nil }

    func summarize(_ notebook: Notebook, in context: ModelContext) async {
        let id = notebook.id
        guard progress[id] == nil else { return }
        guard AppleIntelligence.unavailableReason == nil, #available(iOS 26, *) else {
            errors[id] = AppleIntelligence.unavailableReason
            return
        }
        errors[id] = nil
        progress[id] = "Getting started…"
        defer { progress[id] = nil }
        do {
            try await run(notebook, in: context)
        } catch {
            errors[id] = "Couldn't finish the summary. \(error.localizedDescription)"
        }
    }

    @available(iOS 26, *)
    private func run(_ notebook: Notebook, in context: ModelContext) async throws {
        let id = notebook.id
        let summarizer = OnDeviceNotebookSummarizer()
        let sources = notebook.orderedSources
        let kept = notebook.currentDigests
        // Stored as each source is read, so a failed run doesn't read them again next time.
        var stored = Dictionary(notebook.digests.map { ($0.noteID, $0) }, uniquingKeysWith: { first, _ in first })
        var digests: [SourceDigest] = []
        for (index, note) in sources.enumerated() {
            if var digest = kept[note.id] {
                digest.title = note.title
                digests.append(digest)
                continue
            }
            progress[id] = "Reading “\(note.title)” (\(index + 1) of \(sources.count))…"
            let (title, text, modified) = (note.title, note.sourceText, note.modifiedAt)
            var digest = SourceDigest(noteID: note.id, sourceModifiedAt: modified, title: title, summary: "", keyPoints: [])
            // A source with no text yet is listed but not summarized.
            if !text.isEmpty {
                let reading = "Reading “\(title)” (\(index + 1) of \(sources.count))"
                (digest.summary, digest.keyPoints) = try await summarizer.digest(title: title, text: text) { part, count in
                    guard count > 1 else { return }
                    // Only while the summary is running: a late update must not restart it.
                    Task { @MainActor in
                        if self.progress[id] != nil { self.progress[id] = "\(reading), part \(part) of \(count)…" }
                    }
                }
            }
            guard notebook.modelContext != nil else { return }  // deleted meanwhile
            stored[note.id] = digest
            notebook.digests = Array(stored.values)
            digests.append(digest)
        }

        let readable = digests.filter { !$0.summary.isEmpty }
        guard !readable.isEmpty else {
            notebook.digests = digests
            throw Failure.nothingToRead
        }
        progress[id] = "Writing the overview…"
        let overview = try await summarizer.overview(of: readable)
        guard notebook.modelContext != nil else { return }

        let note = summaryNote(of: notebook, in: context) ?? {
            let note = Note()
            context.insert(note)
            return note
        }()
        note.title = "\(notebook.title) — Summary"
        note.blockDocument = BlockDocument(blocks: NotebookSummary.blocks(overview: overview, digests: readable))
        note.summary = overview.overview
        note.touch()
        notebook.summaryNoteID = note.id
        notebook.digests = digests
        notebook.modifiedAt = .now
    }

    func summaryNote(of notebook: Notebook, in context: ModelContext) -> Note? {
        guard let noteID = notebook.summaryNoteID else { return nil }
        return try? context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteID })).first
    }

    enum Failure: LocalizedError {
        case nothingToRead

        var errorDescription: String? {
            "None of the sources has any text to read yet."
        }
    }
}
