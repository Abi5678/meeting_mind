import Foundation
import Testing

@testable import MeetingMindKit

#if canImport(NaturalLanguage)
@Suite("Related words")
struct RelatedWordsTests {
    @Test("Close words come back weighted; unknown words bring nothing")
    func neighbours() {
        let words = RelatedWords()
        let groceries = words.related(to: "groceries")
        #expect(groceries.contains { $0.term == "grocery" })
        #expect(groceries.allSatisfy { $0.weight > 0 && $0.weight <= 0.5 })
        #expect(words.related(to: "xyzzy").isEmpty)
    }
}
#endif

#if canImport(Vision) && canImport(AppKit)
import AppKit

@Suite("Text recognizer")
struct TextRecognizerTests {
    @Test("Reads printed text from an image")
    func readsText() throws {
        let image = NSImage(size: NSSize(width: 800, height: 200), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            ("Quarterly roadmap review" as NSString).draw(at: NSPoint(x: 40, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 48)])
            return true
        }
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let text = try TextRecognizer.text(in: cgImage)
        #expect(text.localizedCaseInsensitiveContains("roadmap"))
    }
}
#endif

/// The models themselves: slow and only on a machine with Apple Intelligence, so run on request
/// with `ON_DEVICE_AI=1 swift test --filter OnDevice`.
@Suite("On-device models", .enabled(if: ProcessInfo.processInfo.environment["ON_DEVICE_AI"] != nil))
struct OnDeviceModelTests {
    static let script = """
        Good morning. Let's settle the launch. We agreed to move the launch date to March fourteenth. \
        Priya will write the press release by Friday. Sam will update the pricing page.
        """

    /// One speaker teaching, as recorded from the back of a lecture hall.
    static let lecture = """
        Good afternoon everyone. Today I want to walk you through photosynthesis, the way plants \
        turn light into food. It happens in the chloroplasts, and the green pigment chlorophyll is \
        what captures the light. That energy splits water, which is where the oxygen we breathe \
        comes from. Then, in the Calvin cycle, the plant uses that energy to build sugar out of \
        carbon dioxide from the air. So if you remember one thing from today, remember that the \
        mass of a tree comes mostly from the air, not the soil. Next week we will look at how \
        plants respire at night. Please read chapter six before then.
        """

    #if canImport(FoundationModels)
    @Test("Summarizes a meeting without the network")
    @available(macOS 26, *)
    func summary() async throws {
        let analysis = try await OnDeviceMeetingAnalyzer().analyze(transcript: Self.script)
        print("SUMMARY:", analysis.summary, analysis.keyDecisions, analysis.actionItems, analysis.followUpEmail.subject)
        #expect(!analysis.summary.isEmpty)
        #expect(analysis.actionItems.contains { $0.task.localizedCaseInsensitiveContains("press release") })
        #expect(analysis.actionItems.contains { $0.task.localizedCaseInsensitiveContains("pricing") && $0.due == nil })
    }

    @Test("Tells a meeting from a talk")
    @available(macOS 26, *)
    func kind() async throws {
        let analyzer = OnDeviceMeetingAnalyzer()
        #expect(await analyzer.kind(of: Self.script) == .meeting)
        #expect(await analyzer.kind(of: Self.lecture) == .talk)
    }

    @Test("Writes talk notes: key points and takeaways, no email or action items")
    @available(macOS 26, *)
    func talkSummary() async throws {
        let analysis = try await OnDeviceMeetingAnalyzer().analyzeTalk(transcript: Self.lecture)
        print("TALK:", analysis.summary, analysis.keyPoints, analysis.takeaways)
        #expect(!analysis.summary.isEmpty)
        #expect(!analysis.keyPoints.isEmpty)
        #expect(analysis.actionItems.isEmpty && analysis.keyDecisions.isEmpty)
        #expect(analysis.followUpEmail.subject.isEmpty && analysis.followUpEmail.body.isEmpty)
    }

    @Test("A long transcript is condensed in parts first")
    @available(macOS 26, *)
    func longSummary() async throws {
        let long = Array(repeating: Self.script, count: 60).joined(separator: " ")  // ~2,100 words
        let analysis = try await OnDeviceMeetingAnalyzer().analyze(transcript: long)
        print("LONG SUMMARY:", analysis.summary)
        #expect(!analysis.summary.isEmpty)
    }

    @Test("Answers a question from notes and cites the source")
    @available(macOS 26, *)
    func askNotes() async throws {
        let trip = UUID(), launch = UUID()
        let index = SearchIndex(passages:
            SearchPassage.passages(noteID: trip, title: "Trip plan", blocks: [
                Block(type: .paragraph, runs: [.plain("Flights to Lisbon on October 3. Hotel near Alfama.")]),
            ])
            + SearchPassage.passages(noteID: launch, title: "Launch sync", blocks: [], transcript: [
                TranscriptPiece(start: 62, end: 70, text: "We agreed to move the launch date to March fourteenth."),
            ]))
        let sources = NotesQuestion.sources(from: index.search("when is the launch date"),
                                            titles: [trip: "Trip plan", launch: "Launch sync"])
        let answer = try await OnDeviceNotesAnswerer().answer(question: "When is the launch?", sources: sources)
        print("ANSWER:", answer)
        #expect(answer.localizedCaseInsensitiveContains("march"))
        let launchSource = try #require(sources.first { $0.hit.passage.noteID == launch })
        #expect(NotesQuestion.cited(in: answer, count: sources.count).contains(launchSource.number))
    }

    @Test("Writes a gradeable quiz from notes")
    @available(macOS 26, *)
    func quiz() async throws {
        let quiz = try await OnDeviceQuizWriter().quiz(fromNotes: Self.script)
        print("QUIZ:", quiz.title, quiz.questions.map { ($0.prompt, $0.options, $0.answerIndex) })
        #expect(!quiz.questions.isEmpty)
        #expect(quiz.questions.allSatisfy { $0.options.indices.contains($0.answerIndex) })
    }

    @Test("Writes flashcards from notes")
    @available(macOS 26, *)
    func flashcards() async throws {
        let deck = try await OnDeviceFlashcardWriter().deck(fromNotes: Self.script)
        print("FLASHCARDS:", deck.title, deck.cards.map { ($0.front, $0.back) })
        #expect(!deck.cards.isEmpty)
        #expect(deck.cards.allSatisfy { !$0.front.isEmpty && !$0.back.isEmpty })
    }

    @Test("Suggests lowercase topic tags, reusing existing ones")
    @available(macOS 26, *)
    func tags() async throws {
        let tags = try await OnDeviceTagSuggester().tags(title: "Launch sync", notes: Self.script,
                                                         existingTags: ["launch", "recipes"])
        print("TAGS:", tags)
        #expect((1...5).contains(tags.count))
        #expect(tags.allSatisfy { $0 == $0.lowercased() && !$0.hasPrefix("#") })
    }

    @Test("Answers a question about a meeting, and a follow-up")
    @available(macOS 26, *)
    func meetingChat() async throws {
        let chat = OnDeviceMeetingChat()
        let first = try await chat.answer(question: "Who is writing the press release?", transcript: Self.script)
        let followUp = try await chat.answer(question: "By when?", transcript: Self.script, history: [
            MeetingChatTurn(role: .user, text: "Who is writing the press release?"),
            MeetingChatTurn(role: .assistant, text: first),
        ])
        print("CHAT:", first, "|", followUp)
        #expect(first.localizedCaseInsensitiveContains("priya"))
        #expect(followUp.localizedCaseInsensitiveContains("friday"))
    }

    static let libraryMemo = """
        The council voted to fund a new library wing with two million dollars. The money comes from \
        the parks budget, which some members opposed. A final vote on the design is set for March.
        """
    static let libraryPlan = """
        The city planning office expects construction of the library wing to start in spring, once \
        permits are signed. The office estimates the cost at three million dollars, more than the \
        council has set aside.
        """

    @Test("Summarizes each notebook source, then all of them together with citations")
    @available(macOS 26, *)
    func notebookSummary() async throws {
        let summarizer = OnDeviceNotebookSummarizer()
        var digests: [SourceDigest] = []
        for (title, text) in [("Council memo", Self.libraryMemo), ("Planning office note", Self.libraryPlan)] {
            let digest = try await summarizer.digest(title: title, text: text)
            digests.append(SourceDigest(noteID: UUID(), sourceModifiedAt: .now, title: title,
                                        summary: digest.summary, keyPoints: digest.keyPoints))
        }
        let overview = try await summarizer.overview(of: digests)
        print("NOTEBOOK:", digests.map(\.summary), overview)
        #expect(digests.allSatisfy { !$0.summary.isEmpty })
        #expect(!overview.overview.isEmpty)
        #expect(Set(overview.agreements).isDisjoint(with: overview.differences))
        let all = ([overview.overview] + overview.themes + overview.agreements + overview.differences).joined(separator: " ")
        #expect(!NotesQuestion.cited(in: all, count: 2).isEmpty)
    }

    @Test("Answers from a notebook's sources and cites the right one")
    @available(macOS 26, *)
    func notebookChat() async throws {
        let memo = UUID(), plan = UUID()
        let passages = SearchPassage.passages(noteID: memo, title: "Council memo", blocks: [Block(type: .paragraph, runs: [.plain(Self.libraryMemo)])])
            + SearchPassage.passages(noteID: plan, title: "Planning office note", blocks: [Block(type: .paragraph, runs: [.plain(Self.libraryPlan)])])
        let sources = NotebookChat.sources(question: "When does construction start?", passages: passages,
                                           titles: [memo: "Council memo", plan: "Planning office note"])
        let answer = try await OnDeviceNotebookChat().answer(question: "When does construction start?", sources: sources)
        print("NOTEBOOK CHAT:", answer)
        #expect(answer.localizedCaseInsensitiveContains("spring"))
        let cited = NotesQuestion.cited(in: answer, count: sources.count)
        #expect(cited.contains { sources[$0 - 1].noteID == plan })
    }
    #endif

    @Test("Transcribes a recording with timed phrases")
    @available(macOS 26, *)
    func transcription() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "on-device-\(UUID()).aiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(filePath: "/usr/bin/say")
        say.arguments = ["-o", url.path, Self.script]
        try say.run()
        say.waitUntilExit()

        let pieces = try await OnDeviceTranscriber(locale: Locale(identifier: "en_US")).transcribe(fileAt: url)
        print("PIECES:", pieces)
        #expect(TranscriptPiece.joined(pieces).localizedCaseInsensitiveContains("press release"))
        #expect(pieces.last!.end > pieces.first!.start)
    }
}
