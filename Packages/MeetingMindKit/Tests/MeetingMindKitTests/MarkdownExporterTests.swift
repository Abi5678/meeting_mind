import Foundation
import Testing

@testable import MeetingMindKit

@Suite("MarkdownExporter")
struct MarkdownExporterTests {
    /// 2026-07-08T10:00:00Z
    static let date = Date(timeIntervalSince1970: 1_783_504_800)

    private func fullDocument() -> MeetingDocument {
        MeetingDocument(
            title: "Q3 Roadmap — kickoff",
            date: Self.date,
            duration: 2880,
            summary: "The team locked MVP scope.",
            keyDecisions: ["Ship without Notion integration."],
            actionItems: [
                .init(task: "Wireframe the download flow", owner: "Priya", due: "Fri", isDone: true),
                .init(task: "Benchmark small.en", owner: "Unassigned"),
            ],
            followUpEmail: .init(subject: "Recap — kickoff", body: "Hi all,\n\nScope is locked."),
            transcript: "00:00 Abishek: Alright, thanks for jumping on."
        )
    }

    @Test("A fully analysed meeting exports every section in order")
    func exportsEverySection() {
        let markdown = MarkdownExporter.markdown(for: fullDocument())

        #expect(markdown.hasPrefix("# Q3 Roadmap — kickoff\n"))
        #expect(markdown.contains("*Jul 8, 2026 at 10:00 AM · 48m*"))
        #expect(markdown.contains("## Summary\n\nThe team locked MVP scope."))
        #expect(markdown.contains("## Key Decisions\n\n- Ship without Notion integration."))
        #expect(markdown.contains("## Action Items"))
        #expect(markdown.contains("## Follow-up Email\n\n**Subject:** Recap — kickoff"))
        #expect(markdown.contains("## Transcript\n\n00:00 Abishek:"))
        #expect(markdown.hasSuffix("\n"))
    }

    @Test("Sections appear in the order the detail view shows them")
    func sectionOrder() throws {
        let markdown = MarkdownExporter.markdown(for: fullDocument())
        let offsets = try ["## Summary", "## Key Decisions", "## Action Items", "## Follow-up Email", "## Transcript"]
            .map { try #require(markdown.range(of: $0)).lowerBound }

        #expect(offsets == offsets.sorted())
    }

    @Test("Checked and unchecked action items render as task-list checkboxes")
    func actionItemCheckboxes() {
        let markdown = MarkdownExporter.markdown(for: fullDocument())

        #expect(markdown.contains("- [x] Wireframe the download flow — Priya (due Fri)"))
        #expect(markdown.contains("- [ ] Benchmark small.en — Unassigned"))
    }

    @Test("An action item with no owner or due date renders as a bare checkbox")
    func bareActionItem() {
        let document = MeetingDocument(
            title: "Standup",
            date: Self.date,
            duration: 300,
            actionItems: [.init(task: "Fix the flaky test")]
        )
        #expect(MarkdownExporter.markdown(for: document).contains("- [ ] Fix the flaky test\n"))
    }

    @Test("A recorded-but-unanalysed meeting omits the empty sections")
    func omitsEmptySections() {
        let document = MeetingDocument(title: "Untitled", date: Self.date, duration: 65)
        let markdown = MarkdownExporter.markdown(for: document)

        #expect(markdown == "# Untitled\n\n*Jul 8, 2026 at 10:00 AM · 1m*\n")
        #expect(!markdown.contains("## Summary"))
        #expect(!markdown.contains("## Action Items"))
        #expect(!markdown.contains("## Follow-up Email"))
    }

    @Test(
        "Durations read naturally at every scale",
        arguments: [
            (0.0, "0s"),
            (30.0, "30s"),
            (65.0, "1m"),
            (2880.0, "48m"),
            (3600.0, "1h 0m"),
            (5520.0, "1h 32m"),
        ]
    )
    func durationFormatting(duration: TimeInterval, expected: String) {
        let document = MeetingDocument(title: "T", date: Self.date, duration: duration)
        #expect(MarkdownExporter.markdown(for: document).contains("· \(expected)*"))
    }

    @Test("The date is rendered in a fixed locale, so exports do not vary by machine")
    func fixedLocale() {
        let document = MeetingDocument(title: "T", date: Self.date, duration: 60)
        #expect(MarkdownExporter.markdown(for: document).contains("Jul 8, 2026 at 10:00 AM"))
    }

    @Test("A freshly analysed meeting starts with every box unticked")
    func documentFromAnalysis() {
        let document = MeetingDocument(
            title: "Kickoff",
            date: Self.date,
            duration: 2880,
            analysis: Fixture.analysis,
            transcript: "..."
        )
        let markdown = MarkdownExporter.markdown(for: document)

        #expect(document.actionItems.allSatisfy { !$0.isDone })
        #expect(markdown.contains("- [ ] Wireframe the model download flow — Priya (due Fri)"))
        #expect(markdown.contains("- [ ] Benchmark small.en on older devices — Unassigned"))
        #expect(!markdown.contains("- [x]"))
    }
}
