import Foundation

/// Lays a recorded meeting out as note blocks: summary, decisions, action items as to-dos, the
/// follow-up email, then the full transcript last so the useful parts come first.
public enum MeetingNoteBuilder {
    /// - Parameter analysis: nil when the summary could not be written (no Apple Intelligence, or it refused); the note then
    ///   holds the transcript alone.
    public static func blocks(analysis: MeetingAnalysis?, transcript: String) -> [Block] {
        var blocks: [Block] = []
        func add(_ type: BlockType, _ text: String) {
            blocks.append(Block(type: type, runs: [.plain(text)]))
        }

        if let analysis {
            add(.heading(level: 2), "Summary")
            add(.paragraph, analysis.summary)

            if !analysis.keyDecisions.isEmpty {
                add(.heading(level: 2), "Key decisions")
                analysis.keyDecisions.forEach { add(.bulletedList, $0) }
            }

            if !analysis.actionItems.isEmpty {
                add(.heading(level: 2), "Action items")
                analysis.actionItems.forEach { add(.todo, actionItemText($0)) }
            }

            add(.heading(level: 2), "Follow-up email")
            add(.paragraph, "Subject: \(analysis.followUpEmail.subject)")
            paragraphs(analysis.followUpEmail.body).forEach { add(.paragraph, $0) }
        }

        add(.heading(level: 2), "Transcript")
        add(.paragraph, transcript)
        return blocks
    }

    /// "Send the deck (Priya, due Friday)"
    static func actionItemText(_ item: MeetingAnalysis.ActionItem) -> String {
        let details = [item.owner, item.due.map { "due \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }
        return details.isEmpty ? item.task : "\(item.task) (\(details.joined(separator: ", ")))"
    }

    /// One block per non-empty line, since a block is a single paragraph.
    private static func paragraphs(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
