//
//  MeetingArtifact.swift
//  Instant Notes
//

import Foundation
import SwiftData

@Model
final class MeetingArtifact {
    @Attribute(.unique) var id: UUID
    var recordingId: UUID
    var status: Int // raw value of MeetingProcessingStatus
    var summary: String?
    var highlightsJSON: String? // JSON-encoded [MeetingHighlight]
    var fullTranscript: String?
    var createdAt: Date

    var segments: [TranscriptSegment]
    var chatMessages: [MeetingChatMessage]
    var recording: Recording?

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
