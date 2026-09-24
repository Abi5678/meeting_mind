//
//  TranscriptSegment.swift
//  Instant Notes
//

import Foundation
import SwiftData

@Model
final class TranscriptSegment {
    var id: UUID = UUID()
    var artifactId: UUID = UUID()
    var startTime: TimeInterval = 0
    var endTime: TimeInterval = 0
    var text: String = ""

    var artifact: MeetingArtifact?

    init(
        id: UUID = UUID(),
        artifactId: UUID,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String
    ) {
        self.id = id
        self.artifactId = artifactId
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

@Model
final class MeetingChatMessage {
    var id: UUID = UUID()
    var artifactId: UUID = UUID()
    var role: String = "user" // "user" or "assistant"
    var content: String = ""
    var createdAt: Date = Date.now

    var artifact: MeetingArtifact?

    init(
        id: UUID = UUID(),
        artifactId: UUID,
        role: String,
        content: String
    ) {
        self.id = id
        self.artifactId = artifactId
        self.role = role
        self.content = content
        self.createdAt = .now
    }
}

struct MeetingHighlight: Codable, Identifiable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
}
