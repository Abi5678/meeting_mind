import Foundation

/// The summary, decisions, action items and recap email written for one meeting; the summary, key
/// points and takeaways written for one talk; or the summary and sections written for one memo.
public struct MeetingAnalysis: Codable, Equatable, Sendable {
    /// The owner of an action item when the transcript names nobody.
    public static let unassignedOwner = "Unassigned"

    public var summary: String
    public var keyDecisions: [String]
    public var actionItems: [ActionItem]
    public var followUpEmail: FollowUpEmail
    /// A talk's main points, in the order they were made; empty for a meeting.
    public var keyPoints: [String]
    /// What a listener should remember or try after a talk; empty for a meeting.
    public var takeaways: [String]
    /// A few words naming what was recorded ("Banana bread recipe"); empty if none was written.
    public var title: String
    /// A memo's content under headings that suit it, such as Ingredients and Steps; empty otherwise.
    public var sections: [Section]

    public init(
        summary: String,
        keyDecisions: [String],
        actionItems: [ActionItem],
        followUpEmail: FollowUpEmail,
        keyPoints: [String] = [],
        takeaways: [String] = [],
        title: String = "",
        sections: [Section] = []
    ) {
        self.summary = summary
        self.keyDecisions = keyDecisions
        self.actionItems = actionItems
        self.followUpEmail = followUpEmail
        self.keyPoints = keyPoints
        self.takeaways = takeaways
        self.title = title
        self.sections = sections
    }

    public struct Section: Codable, Equatable, Sendable {
        public var heading: String
        public var items: [String]
        /// Steps to follow in order, so they are numbered.
        public var isSteps: Bool

        public init(heading: String, items: [String], isSteps: Bool = false) {
            self.heading = heading
            self.items = items
            self.isSteps = isSteps
        }
    }

    public struct ActionItem: Codable, Equatable, Sendable {
        public var task: String
        /// `MeetingAnalysis.unassignedOwner` when the transcript names nobody.
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
