#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Summarizes a meeting with Apple's on-device model: no network, no API key, and the transcript
/// never leaves the device.
///
/// The model reads about 4,000 tokens at a time, prompt and answer included, so a long meeting is
/// summarized in parts first and the part notes are then summarized together.
@available(iOS 26, macOS 26, *)
public struct OnDeviceMeetingAnalyzer: Sendable {
    /// About 1,300 tokens of English, leaving room for the instructions and the answer.
    static let wordsPerChunk = 900

    public init() {}

    /// Whether the model can run now. It needs a device with Apple Intelligence, turned on, with
    /// the model downloaded.
    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public func analyze(transcript: String) async throws -> MeetingAnalysis {
        var text = transcript
        var chunks = TranscriptChunker.chunks(text, maxWords: Self.wordsPerChunk)
        var isNotes = false
        // Condense part by part until everything fits in one request.
        while chunks.count > 1 {
            var notes: [String] = []
            for (index, chunk) in chunks.enumerated() {
                let session = LanguageModelSession(instructions: Self.instructions)
                let prompt = """
                    This is part \(index + 1) of \(chunks.count) of a meeting \(isNotes ? "summary" : "transcript"). \
                    Note what was discussed, what was decided, and who committed to what.

                    \(chunk)
                    """
                notes.append(try await session.respond(to: prompt, generating: PartNotes.self).content.text)
            }
            text = notes.joined(separator: "\n\n")
            isNotes = true
            chunks = TranscriptChunker.chunks(text, maxWords: Self.wordsPerChunk)
        }

        let session = LanguageModelSession(instructions: Self.instructions)
        let prompt = """
            \(isNotes ? "These are notes on the parts of one meeting, in order." : "This is the transcript of one meeting.") \
            Write the summary, the key decisions, the action items and a follow-up email.

            \(text)
            """
        return try await session.respond(to: prompt, generating: Analysis.self).content.meetingAnalysis
    }

    private static let instructions = """
        You summarize meetings from automatic speech recognition, so expect misheard words and \
        no speaker names. Only state what was said: never invent a name, number, decision or \
        deadline. If nobody was named for a task, the owner is "\(MeetingAnalysis.unassignedOwner)". \
        If no deadline was said, due is nil.
        """

    @Generable
    struct ActionItem {
        @Guide(description: "The work someone committed to do")
        var task: String
        @Guide(description: "Who owns it, as spoken, or Unassigned")
        var owner: String
        @Guide(description: "The deadline as spoken; nil if no deadline was said")
        var due: String?

        /// The model sometimes fills a missing deadline with a placeholder instead of nil.
        var spokenDue: String? {
            guard let due = due?.trimmingCharacters(in: .whitespaces), !due.isEmpty,
                  !["due", "none", "nil", "null", "n/a", "na", "unknown", "not specified", "unspecified", "tbd"].contains(due.lowercased())
            else { return nil }
            return due
        }
    }

    @Generable
    struct PartNotes {
        @Guide(description: "Two or three sentences on what this part covered")
        var summary: String
        @Guide(description: "Choices settled in this part; empty if none")
        var decisions: [String]
        @Guide(description: "Work someone committed to in this part; empty if none")
        var actionItems: [ActionItem]

        var text: String {
            var lines = [summary]
            lines += decisions.map { "Decided: \($0)" }
            lines += actionItems.map { "Action: \($0.task) (owner: \($0.owner)\($0.spokenDue.map { ", due \($0)" } ?? ""))" }
            return lines.joined(separator: "\n")
        }
    }

    @Generable
    struct Analysis {
        @Guide(description: "Three to five sentences: the purpose of the meeting and what came of it")
        var summary: String
        @Guide(description: "Choices the participants settled on; empty if none")
        var keyDecisions: [String]
        @Guide(description: "Concrete work someone committed to; empty if none")
        var actionItems: [ActionItem]
        @Guide(description: "Subject line of a recap email to the attendees")
        var emailSubject: String
        @Guide(description: "A short recap email the organizer could send as is, covering decisions and action items")
        var emailBody: String

        var meetingAnalysis: MeetingAnalysis {
            MeetingAnalysis(
                summary: summary,
                keyDecisions: keyDecisions,
                actionItems: actionItems.map {
                    .init(task: $0.task, owner: $0.owner.isEmpty ? MeetingAnalysis.unassignedOwner : $0.owner,
                          due: $0.spokenDue)
                },
                followUpEmail: .init(subject: emailSubject, body: emailBody)
            )
        }
    }
}
#endif
