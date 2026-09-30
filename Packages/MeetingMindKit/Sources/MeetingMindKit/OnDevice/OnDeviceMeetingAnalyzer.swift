#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Summarizes a meeting or a talk with Apple's on-device model: no network, no API key, and the
/// transcript never leaves the device.
///
/// The model reads about 4,000 tokens at a time, prompt and answer included, so a long recording
/// is summarized in parts first and the part notes are then summarized together.
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
        let (text, isNotes) = try await condensed(transcript, instructions: Self.instructions, as: PartNotes.self) { index, count, isNotes in
            """
            This is part \(index + 1) of \(count) of a meeting \(isNotes ? "summary" : "transcript"). \
            Note what was discussed, what was decided, and who committed to what.
            """
        }

        let session = LanguageModelSession(instructions: Self.instructions)
        let prompt = """
            \(isNotes ? "These are notes on the parts of one meeting, in order." : "This is the transcript of one meeting.") \
            Write the summary, the key decisions, the action items and a follow-up email.

            \(text)
            """
        return try await session.respond(to: prompt, generating: Analysis.self).content.meetingAnalysis
    }

    /// Notes on a talk, lecture or presentation: what it covered, its main points and what to
    /// take away. No decisions, action items or email, since nobody met.
    public func analyzeTalk(transcript: String) async throws -> MeetingAnalysis {
        let (text, isNotes) = try await condensed(transcript, instructions: Self.talkInstructions, as: TalkPartNotes.self) { index, count, isNotes in
            """
            This is part \(index + 1) of \(count) of a talk \(isNotes ? "summary" : "transcript"). \
            Note the points the speaker made and any advice they gave.
            """
        }

        let session = LanguageModelSession(instructions: Self.talkInstructions)
        let prompt = """
            \(isNotes ? "These are notes on the parts of one talk, in order." : "This is the transcript of one talk.") \
            Write the summary, the key points and the takeaways.

            \(text)
            """
        return try await session.respond(to: prompt, generating: TalkAnalysis.self).content.analysis
    }

    /// Whether a transcript is people meeting or one person talking, judged from its opening.
    /// A meeting when the model can't say, since that was the only kind before.
    public func kind(of transcript: String) async -> RecordingKind {
        let opening = TranscriptChunker.chunks(transcript, maxWords: Self.wordsPerChunk).first ?? transcript
        let session = LanguageModelSession(instructions: """
            You sort transcripts from automatic speech recognition, which has no speaker names and \
            may mishear words.
            """)
        let prompt = """
            Is this a talk or a meeting? A talk is one speaker presenting to listeners: a lecture, \
            class, keynote, sermon, podcast or voice memo. It may end with homework or next steps for \
            the audience. A meeting is people working out their own plans together: discussing, \
            deciding and agreeing who does what.

            \(opening)
            """
        guard let sorted = try? await session.respond(to: prompt, generating: Sorting.self).content else { return .meeting }
        return sorted.kind == .talk ? .talk : .meeting
    }

    /// Condenses part by part until everything fits in one request. Returns what to summarize, and
    /// whether that is notes on the parts rather than the transcript itself.
    private func condensed<Notes: PartNoting>(
        _ transcript: String, instructions: String, as _: Notes.Type,
        ask: (_ index: Int, _ count: Int, _ isNotes: Bool) -> String
    ) async throws -> (text: String, isNotes: Bool) {
        var text = transcript
        var chunks = TranscriptChunker.chunks(text, maxWords: Self.wordsPerChunk)
        var isNotes = false
        while chunks.count > 1 {
            var notes: [String] = []
            for (index, chunk) in chunks.enumerated() {
                let session = LanguageModelSession(instructions: instructions)
                let prompt = ask(index, chunks.count, isNotes) + "\n\n" + chunk
                notes.append(try await session.respond(to: prompt, generating: Notes.self).content.text)
            }
            text = notes.joined(separator: "\n\n")
            isNotes = true
            chunks = TranscriptChunker.chunks(text, maxWords: Self.wordsPerChunk)
        }
        return (text, isNotes)
    }

    private static let instructions = """
        You summarize meetings from automatic speech recognition, so expect misheard words and \
        no speaker names. Only state what was said: never invent a name, number, decision or \
        deadline. If nobody was named for a task, the owner is "\(MeetingAnalysis.unassignedOwner)". \
        If no deadline was said, due is nil.
        """

    private static let talkInstructions = """
        You write notes on talks, lectures and presentations from automatic speech recognition, so \
        expect misheard words and no speaker names. Only state what was said: never invent a name, \
        number, fact or piece of advice.
        """

    /// Notes on one part of a long transcript, as text for the next round.
    protocol PartNoting: Generable {
        var text: String { get }
    }

    @Generable
    enum Kind {
        case talk
        case meeting
    }

    @Generable
    struct Sorting {
        // Asked first, so the choice below follows from what the speaking is for.
        @Guide(description: "In a few words, what the speaking is for, e.g. teaching a subject, planning a project")
        var purpose: String
        @Guide(description: "talk if one speaker presents to listeners; meeting if people work out their own plans together")
        var kind: Kind
    }

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
    struct PartNotes: PartNoting {
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

    @Generable
    struct TalkPartNotes: PartNoting {
        @Guide(description: "Two or three sentences on what this part covered")
        var summary: String
        @Guide(description: "The points the speaker made in this part, in order")
        var points: [String]

        var text: String {
            ([summary] + points.map { "Point: \($0)" }).joined(separator: "\n")
        }
    }

    @Generable
    struct TalkAnalysis {
        @Guide(description: "Three to five sentences on what the talk was about")
        var summary: String
        @Guide(description: "The main points the speaker made, in the order they were made")
        var keyPoints: [String]
        @Guide(description: "Things a listener should remember or try, drawn only from what was said; empty if none")
        var takeaways: [String]

        var analysis: MeetingAnalysis {
            MeetingAnalysis(summary: summary, keyDecisions: [], actionItems: [],
                            followUpEmail: .init(subject: "", body: ""),
                            keyPoints: keyPoints, takeaways: takeaways)
        }
    }
}
#endif
