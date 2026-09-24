//
//  Recording.swift
//  Instant Notes
//

import Foundation
import SwiftData
import MeetingMindKit

@Model
final class Recording {
    @Attribute(.unique) var id: UUID
    var name: String
    var filePath: String
    var duration: TimeInterval
    var createdAt: Date
    var isTranscribed: Bool
    /// JSON [AudioClock.Span] for a recording made inside a note, so ink can find its moment in
    /// the audio; nil for other recordings. Defaulted so existing stores migrate lightweight.
    var clockSpansJSON: String? = nil

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

    var clockSpans: [AudioClock.Span] {
        get { clockSpansJSON.flatMap { try? JSONDecoder().decode([AudioClock.Span].self, from: Data($0.utf8)) } ?? [] }
        set { clockSpansJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } }
    }
}
