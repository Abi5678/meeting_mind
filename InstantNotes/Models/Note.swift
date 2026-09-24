//
//  Note.swift
//  Instant Notes
//
// Core note entity with blocks, recordings, and AI metadata.
// Synced with iCloud, so the schema keeps to CloudKit's rules: no unique attributes, a default
// for every value, and optional relationships with explicit inverses.

import Foundation
import SwiftData
import MeetingMindKit

@Model
final class Note {
    var id: UUID = UUID()
    var title: String = "Untitled"
    var createdAt: Date = Date.now
    var modifiedAt: Date = Date.now
    var summary: String?
    var tagsJSON: String = "[]" // JSON-compressed [String]

    var blocksJSON: String = "[]" // JSON-encoded BlockDocument state
    /// PaperStyle raw value; the default lets existing stores migrate without a schema version.
    var paperStyle: String = PaperStyle.lined.rawValue
    /// PaperTint raw value; defaulted for the same reason as `paperStyle`.
    var paperTintName: String = PaperTint.cream.rawValue
    /// PKDrawing data for the ink layer; optional so existing stores migrate lightweight.
    @Attribute(.externalStorage) var drawingData: Data? = nil
    /// Words read from the ink, for search: nil until read (and again after the ink changes),
    /// "" when there are none.
    var inkText: String? = nil
    @Relationship(inverse: \Recording.note) var recordings: [Recording]? = []
    /// Photos shown by the note's image blocks; optional so existing stores migrate lightweight.
    @Relationship(deleteRule: .cascade, inverse: \NoteImage.note) var images: [NoteImage]? = []
    @Relationship(inverse: \MeetingArtifact.note) var meetingArtifact: MeetingArtifact?

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
        set { tagsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    }

    var paper: PaperStyle {
        get { PaperStyle(rawValue: paperStyle) ?? .lined }
        set { paperStyle = newValue.rawValue }
    }

    var paperTint: PaperTint {
        get { PaperTint(rawValue: paperTintName) ?? .cream }
        set { paperTintName = newValue.rawValue }
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
            blocksJSON = (try? JSONEncoder().encode(SwiftDataBlockDocument(document: newValue))).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
    }

    /// Update modified timestamp. Call after every edit.
    func touch() {
        modifiedAt = .now
    }
}
