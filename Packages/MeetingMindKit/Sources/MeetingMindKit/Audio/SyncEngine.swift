//
//  SyncEngine.swift
//  MeetingMindKit
//
//  Pure, unit-testable engine for time↔stroke mapping.
//  Ported from NotabilityClone — unchanged algorithm.
//

import Foundation

/// A mark binding a time offset in an audio recording to a range of stroke indices on a page.
public struct SyncMark: Identifiable, Hashable {
    public let id: UUID
    public let timeOffset: TimeInterval
    public let strokeIndexStart: Int
    public let strokeIndexEnd: Int

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: SyncMark, rhs: SyncMark) -> Bool {
        lhs.id == rhs.id
    }
}

/// Maps audio playback time to ink stroke indices via binary search.
public final class SyncEngine: ObservableObject {
    @Published public var activeMarkID: UUID?
    @Published public var highlightedStrokeIndices: Set<Int> = []

    private var marks: [SyncMark] = []

    /// Update the marks from which time↔stroke mapping is derived.
    public func updateMarks(_ marks: [SyncMark]) {
        self.marks = marks.sorted { $0.timeOffset < $1.timeOffset }
    }

    /// Tick — call on each playback time update to update active mark and highlighted strokes.
    public func tick(currentTime: TimeInterval) {
        updateActiveMark(for: currentTime)
    }

    /// Convert a stroke index back to its corresponding time offset.
    public func timeOffset(forStrokeIndex strokeIndex: Int) -> TimeInterval? {
        for mark in marks {
            let start = min(mark.strokeIndexStart, mark.strokeIndexEnd)
            let end = max(mark.strokeIndexStart, mark.strokeIndexEnd)
            if strokeIndex >= start && strokeIndex <= end {
                return mark.timeOffset
            }
        }
        return nil
    }

    /// Clear all marks and reset state.
    public func clearMarks() {
        marks = []
        activeMarkID = nil
        highlightedStrokeIndices = []
    }

    // MARK: - Internal

    private func updateActiveMark(for currentTime: TimeInterval) {
        guard !marks.isEmpty else {
            activeMarkID = nil
            highlightedStrokeIndices = []
            return
        }

        var left = 0
        var right = marks.count - 1
        var foundIndex: Int?

        while left <= right {
            let mid = (left + right) / 2
            let mark = marks[mid]

            if mark.timeOffset <= currentTime {
                foundIndex = mid
                left = mid + 1
            } else {
                right = mid - 1
            }
        }

        if let index = foundIndex {
            let mark = marks[index]
            activeMarkID = mark.id
            let start = min(mark.strokeIndexStart, mark.strokeIndexEnd)
            let end = max(mark.strokeIndexStart, mark.strokeIndexEnd)
            highlightedStrokeIndices = Set(start...end)
        } else {
            activeMarkID = nil
            highlightedStrokeIndices = []
        }
    }
}

/// Convert an array of `TimedMark` entries into `SyncMark` objects.
public func syncMarks(from marks: [TimedMark]) -> [SyncMark] {
    marks.map { mark in
        SyncMark(
            id: mark.id,
            timeOffset: mark.timeOffset,
            strokeIndexStart: mark.strokeIndexStart,
            strokeIndexEnd: mark.strokeIndexEnd
        )
    }
}
