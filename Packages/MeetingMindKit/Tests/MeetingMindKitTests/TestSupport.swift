import Foundation

@testable import MeetingMindKit

enum Fixture {
    static let analysis = MeetingAnalysis(
        summary: "The team locked MVP scope and cut Notion sync.",
        keyDecisions: ["Ship without Notion integration.", "Default model is base.en-q5_1."],
        actionItems: [
            .init(task: "Wireframe the model download flow", owner: "Priya", due: "Fri"),
            .init(task: "Benchmark small.en on older devices", owner: "Unassigned"),
        ],
        followUpEmail: .init(subject: "Recap — kickoff", body: "Hi all,\n\nScope is locked.\n\n— Abishek")
    )
}
