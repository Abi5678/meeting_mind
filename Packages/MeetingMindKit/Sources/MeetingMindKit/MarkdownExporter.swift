import Foundation

/// What the app knows about a meeting at export time.
///
/// This is deliberately not `MeetingAnalysis`: action items gain an `isDone` checkbox once
/// they are persisted, and the Kit must stay free of SwiftData.
public struct MeetingDocument: Sendable {
    public var title: String
    public var date: Date
    public var duration: TimeInterval
    public var summary: String?
    public var keyDecisions: [String]
    public var actionItems: [ActionItem]
    public var followUpEmail: MeetingAnalysis.FollowUpEmail?
    public var transcript: String?

    public struct ActionItem: Sendable {
        public var task: String
        public var owner: String?
        public var due: String?
        public var isDone: Bool

        public init(task: String, owner: String? = nil, due: String? = nil, isDone: Bool = false) {
            self.task = task
            self.owner = owner
            self.due = due
            self.isDone = isDone
        }
    }

    public init(
        title: String,
        date: Date,
        duration: TimeInterval,
        summary: String? = nil,
        keyDecisions: [String] = [],
        actionItems: [ActionItem] = [],
        followUpEmail: MeetingAnalysis.FollowUpEmail? = nil,
        transcript: String? = nil
    ) {
        self.title = title
        self.date = date
        self.duration = duration
        self.summary = summary
        self.keyDecisions = keyDecisions
        self.actionItems = actionItems
        self.followUpEmail = followUpEmail
        self.transcript = transcript
    }

    /// A freshly analysed meeting, before anyone has ticked any boxes.
    public init(
        title: String,
        date: Date,
        duration: TimeInterval,
        analysis: MeetingAnalysis,
        transcript: String? = nil
    ) {
        self.init(
            title: title,
            date: date,
            duration: duration,
            summary: analysis.summary,
            keyDecisions: analysis.keyDecisions,
            actionItems: analysis.actionItems.map {
                ActionItem(task: $0.task, owner: $0.owner, due: $0.due)
            },
            followUpEmail: analysis.followUpEmail,
            transcript: transcript
        )
    }
}

public enum MarkdownExporter {
    /// Empty sections are omitted, so a meeting that has been transcribed but not yet analysed
    /// still exports cleanly.
    public static func markdown(for document: MeetingDocument) -> String {
        var sections: [String] = [
            "# \(document.title)",
            "*\(formatted(document.date)) · \(formatted(duration: document.duration))*",
        ]

        if let summary = document.summary, !summary.isEmpty {
            sections.append("## Summary\n\n\(summary)")
        }

        if !document.keyDecisions.isEmpty {
            let lines = document.keyDecisions.map { "- \($0)" }.joined(separator: "\n")
            sections.append("## Key Decisions\n\n\(lines)")
        }

        if !document.actionItems.isEmpty {
            let lines = document.actionItems.map(line(for:)).joined(separator: "\n")
            sections.append("## Action Items\n\n\(lines)")
        }

        if let email = document.followUpEmail {
            sections.append("## Follow-up Email\n\n**Subject:** \(email.subject)\n\n\(email.body)")
        }

        if let transcript = document.transcript, !transcript.isEmpty {
            sections.append("## Transcript\n\n\(transcript)")
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    private static func line(for item: MeetingDocument.ActionItem) -> String {
        var line = "- [\(item.isDone ? "x" : " ")] \(item.task)"
        if let owner = item.owner, !owner.isEmpty {
            line += " — \(owner)"
        }
        if let due = item.due, !due.isEmpty {
            line += " (due \(due))"
        }
        return line
    }

    /// Fixed locale and time zone: the export is a document, not a UI string, and the tests
    /// must not depend on where the machine is.
    private static func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }

    private static func formatted(duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60

        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }
}
