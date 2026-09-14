//
//  Tag.swift
//  Instant Notes
//

import Foundation
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String // hex string for UI, e.g. "#2D4C6B"

    init(id: UUID = UUID(), name: String, colorHex: String = "#000000") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

// MARK: - Database models (Phase 5 — planned)

@Model
final class TableEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var noteId: UUID

    init(id: UUID = UUID(), title: String, noteId: UUID) {
        self.id = id
        self.title = title
        self.noteId = noteId
    }
}

@Model
final class ColumnEntity {
    @Attribute(.unique) var id: UUID
    var tableId: UUID
    var name: String
    var columnType: String // "text", "number", "date", "checkbox", "select"

    init(id: UUID = UUID(), tableId: UUID, name: String, columnType: String) {
        self.id = id
        self.tableId = tableId
        self.name = name
        self.columnType = columnType
    }
}

@Model
final class RowEntity {
    @Attribute(.unique) var id: UUID
    var tableId: UUID
    var valuesJSON: String // JSON-encoded [UUID: String] keyed by column id

    init(id: UUID = UUID(), tableId: UUID, valuesJSON: String = "{}") {
        self.id = id
        self.tableId = tableId
        self.valuesJSON = valuesJSON
    }
}
