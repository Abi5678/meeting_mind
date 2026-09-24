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
