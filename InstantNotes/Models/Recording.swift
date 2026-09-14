//
//  Recording.swift
//  Instant Notes
//

import Foundation
import SwiftData

@Model
final class Recording {
    @Attribute(.unique) var id: UUID
    var name: String
    var filePath: String
    var duration: TimeInterval
    var createdAt: Date
    var isTranscribed: Bool

    // Relationship back to the note (CloudKit-shaped: optional with inverse)
    var note: Note?

    init(
        id: UUID = UUID(),
        name: String,
        filePath: String,
        duration: TimeInterval,
        createdAt: Date = .now,
        isTranscribed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.filePath = filePath
        self.duration = duration
        self.createdAt = createdAt
        self.isTranscribed = isTranscribed
    }
}
