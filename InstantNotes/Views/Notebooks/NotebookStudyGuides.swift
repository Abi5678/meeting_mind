//
//  NotebookStudyGuides.swift
//  Instant Notes
//
// Writes a notebook's study guide with Apple's on-device model: key terms, questions to test
// yourself with and questions to think over, from all its sources, into the notebook's study guide
// note. Shared across the app, so a guide keeps going when you leave the notebook.

import Foundation
import SwiftData
import MeetingMindKit

@MainActor
@Observable
final class NotebookStudyGuides {
    static let shared = NotebookStudyGuides()

    /// Notebooks whose study guide is being written.
    private(set) var writing: Set<UUID> = []
    /// Why the last study guide of a notebook failed.
    private(set) var errors: [UUID: String] = [:]

    func write(_ notebook: Notebook, in context: ModelContext) async {
        let id = notebook.id
        guard !writing.contains(id) else { return }
        guard AppleIntelligence.unavailableReason == nil, #available(iOS 26, *) else {
            errors[id] = AppleIntelligence.unavailableReason
            return
        }
        errors[id] = nil
        writing.insert(id)
        defer { writing.remove(id) }
        do {
            let guide = try await OnDeviceStudyGuideWriter().guide(title: notebook.title, material: notebook.studyMaterial)
            guard notebook.modelContext != nil else { return }  // deleted meanwhile
            let note = studyGuideNote(of: notebook, in: context) ?? {
                let note = Note()
                context.insert(note)
                return note
            }()
            note.title = "\(notebook.title) — Study guide"
            note.blockDocument = BlockDocument(blocks: NotebookStudy.blocks(guide))
            note.touch()
            notebook.studyGuideNoteID = note.id
            notebook.modifiedAt = .now
        } catch OnDeviceAIError.emptyNotebook, OnDeviceAIError.notEnoughContent {
            errors[id] = "There isn't enough in these sources for a study guide yet."
        } catch {
            errors[id] = "Couldn't write the study guide. \(error.localizedDescription)"
        }
    }

    func studyGuideNote(of notebook: Notebook, in context: ModelContext) -> Note? {
        guard let noteID = notebook.studyGuideNoteID else { return nil }
        return try? context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteID })).first
    }
}
