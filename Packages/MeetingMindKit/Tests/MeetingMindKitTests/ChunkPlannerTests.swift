import Testing

@testable import MeetingMindKit

@Suite("ChunkPlanner")
struct ChunkPlannerTests {
    static let sampleRate = 16_000
    static let window = 120 * sampleRate  // 1_920_000
    static let frame = 320  // 20 ms
    static let searchSpan = 5 * sampleRate  // 80_000
    static let minimumChunk = 5 * sampleRate  // 80_000

    /// Flat energy plus the "latest quiet frame wins" tie-break means cuts land on `idealEnd`.
    static let flat: @Sendable (Range<Int>) -> Float = { _ in 1 }

    @Test("Empty or invalid input yields no chunks")
    func emptyInput() {
        #expect(ChunkPlanner.plan(totalSamples: 0, sampleRate: Self.sampleRate).isEmpty)
        #expect(ChunkPlanner.plan(totalSamples: -1, sampleRate: Self.sampleRate).isEmpty)
        #expect(ChunkPlanner.plan(totalSamples: 1000, sampleRate: 0).isEmpty)
    }

    @Test("Audio shorter than one window is a single chunk")
    func shorterThanWindow() {
        let total = 60 * Self.sampleRate
        let ranges = ChunkPlanner.plan(totalSamples: total, sampleRate: Self.sampleRate)
        #expect(ranges == [ChunkRange(startSample: 0, endSample: total)])
    }

    @Test("Audio of exactly one window is a single chunk, not two")
    func exactlyOneWindow() {
        let ranges = ChunkPlanner.plan(totalSamples: Self.window, sampleRate: Self.sampleRate)
        #expect(ranges == [ChunkRange(startSample: 0, endSample: Self.window)])
    }

    @Test("Uniform energy cuts exactly on the window boundary")
    func uniformEnergyCutsOnBoundary() {
        let total = 240 * Self.sampleRate
        let ranges = ChunkPlanner.plan(totalSamples: total, sampleRate: Self.sampleRate, energy: Self.flat)

        #expect(ranges == [
            ChunkRange(startSample: 0, endSample: Self.window),
            ChunkRange(startSample: Self.window, endSample: total),
        ])
    }

    @Test("The cut snaps to the end of the quietest frame in the search tail")
    func snapsToQuietestFrame() {
        let total = 240 * Self.sampleRate
        let searchStart = Self.window - Self.searchSpan
        let dipStart = searchStart + Self.frame * 10
        let dipEnd = dipStart + Self.frame

        let ranges = ChunkPlanner.plan(totalSamples: total, sampleRate: Self.sampleRate) { range in
            range.lowerBound == dipStart ? 0 : 1
        }

        #expect(ranges.first?.endSample == dipEnd)
        #expect(ranges.count == 2)
        #expect(ranges.last == ChunkRange(startSample: dipEnd, endSample: total))
    }

    @Test("Silence before the search tail is ignored")
    func ignoresSilenceOutsideTail() {
        let total = 240 * Self.sampleRate
        let tooEarly = Self.window - Self.searchSpan - Self.frame * 4

        let ranges = ChunkPlanner.plan(totalSamples: total, sampleRate: Self.sampleRate) { range in
            range.lowerBound == tooEarly ? 0 : 1
        }

        #expect(ranges.first?.endSample == Self.window)
    }

    @Test("A one-sample tail is folded into its predecessor instead of becoming a chunk")
    func foldsRuntTail() {
        let total = Self.window + 1
        let ranges = ChunkPlanner.plan(totalSamples: total, sampleRate: Self.sampleRate)
        #expect(ranges == [ChunkRange(startSample: 0, endSample: total)])
    }

    @Test("A tail below the minimum folds; a tail at the minimum stands on its own")
    func minimumTailBoundary() {
        let folded = ChunkPlanner.plan(
            totalSamples: Self.window + Self.minimumChunk - 1,
            sampleRate: Self.sampleRate,
            energy: Self.flat
        )
        #expect(folded.count == 1)

        let split = ChunkPlanner.plan(
            totalSamples: Self.window + Self.minimumChunk,
            sampleRate: Self.sampleRate,
            energy: Self.flat
        )
        #expect(split.count == 2)
        #expect(split.last?.sampleCount == Self.minimumChunk)
    }

    @Test(
        "No chunk falls below the minimum, whatever the remainder",
        arguments: [1, 320, minimumChunk - 1, minimumChunk, searchSpan, window - 1]
    )
    func noRuntChunks(extra: Int) {
        let total = Self.window + extra
        let ranges = ChunkPlanner.plan(totalSamples: total, sampleRate: Self.sampleRate, energy: Self.flat)

        #expect(ranges.last?.endSample == total)
        #expect(ranges.allSatisfy { $0.sampleCount >= Self.minimumChunk })
    }

    @Test("Chunks are contiguous, non-empty, and cover the whole file")
    func chunksTileTheFile() {
        let total = 400 * Self.sampleRate + 7  // deliberately not a round number of frames

        // Deterministic, uneven energy — no randomness, so the test cannot flake.
        let ranges = ChunkPlanner.plan(totalSamples: total, sampleRate: Self.sampleRate) { range in
            Float((range.lowerBound / Self.frame) % 7)
        }

        #expect(ranges.count > 1)
        #expect(ranges.first?.startSample == 0)
        #expect(ranges.last?.endSample == total)
        #expect(ranges.allSatisfy { $0.sampleCount >= Self.minimumChunk })

        for (earlier, later) in zip(ranges, ranges.dropFirst()) {
            #expect(earlier.endSample == later.startSample)
        }
    }

    @Test("All-silent audio still terminates and tiles the file")
    func allSilentTerminates() {
        let total = 500 * Self.sampleRate
        let ranges = ChunkPlanner.plan(totalSamples: total, sampleRate: Self.sampleRate) { _ in 0 }

        #expect(ranges.last?.endSample == total)
        #expect(ranges.allSatisfy { $0.sampleCount > 0 })
    }

    @Test("A chunk reports its offset into the meeting")
    func chunkTiming() {
        let chunk = ChunkRange(startSample: Self.window, endSample: Self.window + 16_000)
        #expect(chunk.startTime(sampleRate: Self.sampleRate) == 120)
        #expect(chunk.duration(sampleRate: Self.sampleRate) == 1)
        #expect(chunk.sampleCount == 16_000)
    }

    @Test("A 90-minute meeting chunks into flat-memory windows")
    func ninetyMinuteMeeting() {
        let total = 90 * 60 * Self.sampleRate
        let ranges = ChunkPlanner.plan(totalSamples: total, sampleRate: Self.sampleRate, energy: Self.flat)

        #expect(ranges.count == 45)
        // 120 s of 16 kHz mono Float32 is 7.7 MB, so memory stays flat across the meeting.
        #expect(ranges.allSatisfy { $0.sampleCount <= Self.window + Self.minimumChunk })
    }
}
