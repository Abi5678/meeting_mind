//
//  Recording.swift
//  Instant Notes
//

import Foundation
import SwiftData
import MeetingMindKit

@Model
final class Recording {
    var id: UUID = UUID()
    var name: String = ""
    /// The audio file's name in the recordings folder, a local copy of `audioData`.
    var filePath: String = ""
    var duration: TimeInterval = 0
    var createdAt: Date = Date.now
    var isTranscribed: Bool = false
    /// The audio itself, stored in the database so it syncs with iCloud; the file at `filePath`
    /// is written from it on a device that doesn't have one yet.
    @Attribute(.externalStorage) var audioData: Data? = nil
    /// JSON [AudioClock.Span] for a recording made inside a note, so ink can find its moment in
    /// the audio; nil for other recordings. Defaulted so existing stores migrate lightweight.
    var clockSpansJSON: String? = nil
    /// Where this recording's words start in its note's meeting transcript, which runs a note's
    /// recordings end to end. 0 for the first, and for recordings saved before this existed.
    var transcriptOffset: TimeInterval = 0

    // Relationships back to the note and its meeting; the inverses are declared on the other side.
    var note: Note?
    var artifact: MeetingArtifact?

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
