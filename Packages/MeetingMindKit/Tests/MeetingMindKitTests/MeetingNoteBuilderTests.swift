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

    @Test("A talk becomes summary, key points, takeaways, then transcript, with no email")
    func talkLayout() {
        let analysis = MeetingAnalysis(
            summary: "How plants make sugar.",
            keyDecisions: [], actionItems: [], followUpEmail: .init(subject: "", body: ""),
            keyPoints: ["Light is captured by chlorophyll.", "Sugar is built from carbon dioxide."],
            takeaways: ["Leaves are green because they reflect green light."]
        )

        let blocks = MeetingNoteBuilder.blocks(kind: .talk, analysis: analysis, transcript: "today we look at leaves")

        #expect(Self.layout(blocks) == [
            "h Summary", "p How plants make sugar.",
            "h Key points", "- Light is captured by chlorophyll.", "- Sugar is built from carbon dioxide.",
            "h Takeaways", "- Leaves are green because they reflect green light.",
            "h Transcript", "p today we look at leaves",
        ])
    }

    @Test("A talk with no key points or takeaways leaves out their headings")
    func talkEmptySectionsOmitted() {
        let analysis = MeetingAnalysis(summary: "A short hello.", keyDecisions: [], actionItems: [],
                                       followUpEmail: .init(subject: "", body: ""))
        let blocks = MeetingNoteBuilder.blocks(kind: .talk, analysis: analysis, transcript: "hi")
        #expect(Self.layout(blocks) == ["h Summary", "p A short hello.", "h Transcript", "p hi"])
    }

    @Test("A song is kept as its lyrics, even if something summarized it")
    func songLayout() {
        let blocks = MeetingNoteBuilder.blocks(kind: .song, analysis: Fixture.analysis, transcript: "never gonna give you up")
        #expect(Self.layout(blocks) == ["h Lyrics", "p never gonna give you up"])
    }

    @Test("Action item details include only what was stated")
    func actionItemText() {
        #expect(MeetingNoteBuilder.actionItemText(.init(task: "Book room")) == "Book room")
        #expect(MeetingNoteBuilder.actionItemText(.init(task: "Book room", owner: "Sam")) == "Book room (Sam)")
        #expect(MeetingNoteBuilder.actionItemText(.init(task: "Book room", owner: "", due: "noon")) == "Book room (due noon)")
    }
}
