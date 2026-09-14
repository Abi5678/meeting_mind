//
//  Note.swift
//  Instant Notes
//
// Core note entity with blocks, recordings, and AI metadata.
// CloudKit-shaped schema from day one: all relationships optional with inverses.

import Foundation
import SwiftData

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var summary: String?
    var tagsJSON: String // JSON-compressed [String]

    var blocksJSON: String // JSON-encoded BlockDocument state
    var recordings: [Recording]
    var meetingArtifact: MeetingArtifact?

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        summary: String? = nil,
        tagsJSON: String = "[]",
        blocksJSON: String = "[]"
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.summary = summary
        self.tagsJSON = tagsJSON
        self.blocksJSON = blocksJSON
        self.recordings = []
        self.meetingArtifact = nil
    }

    // MARK: - Computed helpers

    var tags: [String] {
        get { (try? JSONDecoder().decode([String].self, from: tagsJSON.data(using: .utf8) ?? Data())) ?? [] }
        set { tagsJSON = (try? JSONEncoder().encode(newValue)) ?? "[]" }
    }

    var blockDocument: BlockDocument {
        get {
            guard let data = blocksJSON.data(using: .utf8),
                  let doc = try? JSONDecoder().decode(SwiftDataBlockDocument.self, from: data) else {
                return BlockDocument()
            }
            return doc.document
        }
        set {
            blocksJSON = (try? JSONEncoder().encode(SwiftDataBlockDocument(document: newValue)).data(using: .utf8)) ?? "[]"
        }
    }

    /// Update modified timestamp. Call after every edit.
    func touch() {
        modifiedAt = .now
    }
}
