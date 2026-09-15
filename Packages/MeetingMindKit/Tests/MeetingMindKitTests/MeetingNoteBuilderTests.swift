import Testing

@testable import MeetingMindKit

@Suite("MeetingNoteBuilder")
struct MeetingNoteBuilderTests {
    private static func layout(_ blocks: [Block]) -> [String] {
        blocks.map { block in
            let kind = switch block.type {
            case .heading: "h"
            case .bulletedList: "-"
            case .todo: "[ ]"
            default: "p"
            }
            return "\(kind) \(block.plainText)"
        }
    }

    @Test("A full analysis becomes summary, decisions, to-dos, email, then transcript")
    func fullAnalysis() {
        let analysis = MeetingAnalysis(
            summary: "We planned the launch.",
            keyDecisions: ["Launch on Monday."],
            actionItems: [.init(task: "Send the deck", owner: "Priya", due: "Friday")],
            followUpEmail: .init(subject: "Launch recap", body: "Hi all,\n\nWe launch Monday.")
        )

        let blocks = MeetingNoteBuilder.blocks(analysis: analysis, transcript: "okay so the launch")

        #expect(Self.layout(blocks) == [
            "h Summary", "p We planned the launch.",
            "h Key decisions", "- Launch on Monday.",
            "h Action items", "[ ] Send the deck (Priya, due Friday)",
            "h Follow-up email", "p Subject: Launch recap", "p Hi all,", "p We launch Monday.",
            "h Transcript", "p okay so the launch",
        ])
    }

    @Test("Empty decision and action lists leave out their headings")
    func emptySectionsOmitted() {
        let analysis = MeetingAnalysis(summary: "Too short.", keyDecisions: [], actionItems: [],
                                       followUpEmail: .init(subject: "Recap", body: "Nothing decided."))
        let headings = MeetingNoteBuilder.blocks(analysis: analysis, transcript: "hi")
            .filter { if case .heading = $0.type { true } else { false } }
            .map(\.plainText)
        #expect(headings == ["Summary", "Follow-up email", "Transcript"])
    }

    @Test("Without an analysis the note is just the transcript")
    func transcriptOnly() {
        let blocks = MeetingNoteBuilder.blocks(analysis: nil, transcript: "hello there")
        #expect(Self.layout(blocks) == ["h Transcript", "p hello there"])
    }

    @Test("Action item details include only what was stated")
    func actionItemText() {
        #expect(MeetingNoteBuilder.actionItemText(.init(task: "Book room")) == "Book room")
        #expect(MeetingNoteBuilder.actionItemText(.init(task: "Book room", owner: "Sam")) == "Book room (Sam)")
        #expect(MeetingNoteBuilder.actionItemText(.init(task: "Book room", owner: "", due: "noon")) == "Book room (due noon)")
    }
}
