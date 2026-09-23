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
