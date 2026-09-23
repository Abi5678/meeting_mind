#if canImport(Speech)
import Testing
@testable import MeetingMindKit

@Suite("Speech file transcriber windows")
struct SpeechFileTranscriberTests {
    struct Boom: Error, Equatable {}

    actor Progress {
        private(set) var reports: [[Int]] = []
        func record(_ window: Int, _ total: Int) { reports.append([window, total]) }
    }

    @Test("Every window's text is joined, silent windows skipped, progress reported per window")
    func allSucceed() async throws {
        let progress = Progress()
        let texts = ["Hello there.", "", "Next item."]
        let transcript = try await SpeechFileTranscriber.transcribeWindows(3, progress: { await progress.record($0, $1) }) {
            texts[$0]
        }
        #expect(transcript == "Hello there. Next item.")
        #expect(await progress.reports == [[1, 3], [2, 3], [3, 3]])
    }

    @Test("A failed window keeps the rest of the meeting")
    func middleFails() async {
        var tried: [Int] = []
        await #expect(throws: SpeechFileTranscriber.Failure.incomplete(transcript: "a c", failedParts: 1, totalParts: 3)) {
            try await SpeechFileTranscriber.transcribeWindows(3, progress: { _, _ in }) { index in
                tried.append(index)
                if index == 1 { throw Boom() }
                return ["a", "b", "c"][index]
            }
        }
        #expect(tried == [0, 1, 2])
    }

    @Test("When every window fails the original error comes through")
    func allFail() async {
        await #expect(throws: Boom()) {
            try await SpeechFileTranscriber.transcribeWindows(2, progress: { _, _ in }) { _ in throw Boom() }
        }
    }

    @Test("Cancellation stops at once instead of counting as a failed window")
    func cancellation() async {
        var tried: [Int] = []
        await #expect(throws: CancellationError.self) {
            try await SpeechFileTranscriber.transcribeWindows(3, progress: { _, _ in }) { index in
                tried.append(index)
                if index == 1 { throw CancellationError() }
                return "a"
            }
        }
        #expect(tried == [0, 1])
    }
}
#endif
