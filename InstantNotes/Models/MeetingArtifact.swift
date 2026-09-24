//
//  MeetingArtifact.swift
//  Instant Notes
//

import Foundation
import SwiftData

@Model
final class MeetingArtifact {
    var id: UUID = UUID()
    var recordingId: UUID = UUID()
    var status: Int = 0 // raw value of MeetingProcessingStatus
    var summary: String?
    var highlightsJSON: String? // JSON-encoded [MeetingHighlight]
    var fullTranscript: String?
    var createdAt: Date = Date.now

    @Relationship(inverse: \TranscriptSegment.artifact) var segments: [TranscriptSegment]? = []
    @Relationship(inverse: \MeetingChatMessage.artifact) var chatMessages: [MeetingChatMessage]? = []
    @Relationship(inverse: \Recording.artifact) var recording: Recording?
    var note: Note?

    init(
        id: UUID = UUID(),
        recordingId: UUID,
        status: Int,
        summary: String? = nil,
        highlightsJSON: String? = nil,
        fullTranscript: String? = nil
    ) {
        self.id = id
        self.recordingId = recordingId
        self.status = status
        self.summary = summary
        self.highlightsJSON = highlightsJSON
        self.fullTranscript = fullTranscript
        self.createdAt = .now
        self.segments = []
        self.chatMessages = []
    }

    var processingStatus: MeetingProcessingStatus {
        get { MeetingProcessingStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }
}

public enum MeetingProcessingStatus: Int, Codable, Identifiable, CaseIterable {
    case pending, transcribing, summarizing, ready, failed

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .pending: "Pending"
        case .transcribing: "Transcribing"
        case .summarizing: "Summarizing"
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }

    public var displayColor: String {
        switch self {
        case .pending: "gray"
        case .transcribing: "blue"
        case .summarizing: "purple"
        case .ready: "green"
        case .failed: "red"
        }
    }
}
