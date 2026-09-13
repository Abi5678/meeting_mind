import Foundation

/// A half-open range of audio samples, `[startSample, endSample)`.
public struct ChunkRange: Equatable, Sendable {
    public let startSample: Int
    public let endSample: Int

    public init(startSample: Int, endSample: Int) {
        self.startSample = startSample
        self.endSample = endSample
    }

    public var sampleCount: Int { endSample - startSample }

    /// Whisper reports timestamps relative to the chunk; add this to get meeting-relative ones.
    public func startTime(sampleRate: Int) -> TimeInterval {
        TimeInterval(startSample) / TimeInterval(sampleRate)
    }

    public func duration(sampleRate: Int) -> TimeInterval {
        TimeInterval(sampleCount) / TimeInterval(sampleRate)
    }
}

/// Splits an audio file into whisper-sized windows without ever holding the whole file.
///
/// A 120 s window at 16 kHz mono Float32 is 7.7 MB, so memory stays flat regardless of
/// meeting length. Cuts are snapped to the quietest 20 ms frame near the window's end so a
/// chunk boundary rarely lands mid-word.
public enum ChunkPlanner {
    public static let targetWindowSeconds: TimeInterval = 120
    /// How far back from the ideal cut to hunt for silence.
    public static let boundarySearchSeconds: TimeInterval = 5
    public static let energyFrameSeconds: TimeInterval = 0.020
    /// A trailing chunk shorter than this is folded into its predecessor. whisper pads short
    /// input up to 30 s and readily hallucinates over the padding, so one slightly over-long
    /// chunk beats a runt. Without this, a file of `window + 1` samples ends in a 1-sample chunk.
    public static let minimumChunkSeconds: TimeInterval = 5

    /// Uniform windows, no silence snapping. Useful when sample energy is not available.
    public static func plan(totalSamples: Int, sampleRate: Int) -> [ChunkRange] {
        plan(totalSamples: totalSamples, sampleRate: sampleRate) { _ in 0 }
    }

    /// - Parameter energy: mean energy of the samples in the given half-open range. Any
    ///   monotonic measure works (RMS, mean square); only the ordering matters.
    public static func plan(
        totalSamples: Int,
        sampleRate: Int,
        energy: (Range<Int>) -> Float
    ) -> [ChunkRange] {
        guard totalSamples > 0, sampleRate > 0 else { return [] }

        let window = Int(targetWindowSeconds * TimeInterval(sampleRate))
        let searchSpan = Int(boundarySearchSeconds * TimeInterval(sampleRate))
        let frame = max(1, Int(energyFrameSeconds * TimeInterval(sampleRate)))
        let minimumChunk = Int(minimumChunkSeconds * TimeInterval(sampleRate))

        var ranges: [ChunkRange] = []
        var start = 0

        while start < totalSamples {
            let idealEnd = start + window

            // Snapping only ever moves the cut earlier, so testing the remainder against the
            // *ideal* end is enough to keep every subsequent chunk at or above the minimum.
            let remainder = totalSamples - idealEnd
            guard idealEnd < totalSamples, remainder >= minimumChunk else {
                ranges.append(ChunkRange(startSample: start, endSample: totalSamples))
                break
            }

            let searchStart = max(start, idealEnd - searchSpan)
            let end = quietestBoundary(from: searchStart, to: idealEnd, frame: frame, energy: energy)
            ranges.append(ChunkRange(startSample: start, endSample: end))
            start = end
        }

        return ranges
    }

    /// Returns the end of the quietest whole 20 ms frame in `[searchStart, idealEnd)`, so the
    /// silence stays with the earlier chunk.
    ///
    /// Ties resolve to the *latest* quiet frame, which makes uniform-energy audio cut exactly
    /// at `idealEnd`. When no whole frame fits, `idealEnd` is returned — always greater than
    /// the chunk's start, so the caller cannot loop forever.
    private static func quietestBoundary(
        from searchStart: Int,
        to idealEnd: Int,
        frame: Int,
        energy: (Range<Int>) -> Float
    ) -> Int {
        var boundary = idealEnd
        var quietest = Float.greatestFiniteMagnitude
        var frameStart = searchStart

        while frameStart + frame <= idealEnd {
            let frameEnd = frameStart + frame
            let level = energy(frameStart..<frameEnd)
            if level <= quietest {
                quietest = level
                boundary = frameEnd
            }
            frameStart = frameEnd
        }

        return boundary
    }
}
