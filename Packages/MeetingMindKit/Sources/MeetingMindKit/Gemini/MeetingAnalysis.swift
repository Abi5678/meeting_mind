import Foundation

/// The structured analysis Gemini returns for a single meeting transcript.
///
/// The shape here is mirrored by `GeminiSchema.meetingAnalysis`, which is sent as the
/// request's `responseSchema`. Keep the two in sync.
public struct MeetingAnalysis: Codable, Equatable, Sendable {
    public var summary: String
    public var keyDecisions: [String]
    public var actionItems: [ActionItem]
    public var followUpEmail: FollowUpEmail

    public init(
        summary: String,
        keyDecisions: [String],
        actionItems: [ActionItem],
        followUpEmail: FollowUpEmail
    ) {
        self.summary = summary
        self.keyDecisions = keyDecisions
        self.actionItems = actionItems
        self.followUpEmail = followUpEmail
    }

    public struct ActionItem: Codable, Equatable, Sendable {
        public var task: String
        /// `PromptBuilder.unassignedOwner` when the transcript names nobody.
        public var owner: String?
        /// Free text as spoken ("Friday", "end of Q3"), not a parsed date.
        public var due: String?

        public init(task: String, owner: String? = nil, due: String? = nil) {
            self.task = task
            self.owner = owner
            self.due = due
        }
    }

    public struct FollowUpEmail: Codable, Equatable, Sendable {
        public var subject: String
        public var body: String

        public init(subject: String, body: String) {
            self.subject = subject
            self.body = body
        }
    }
}
