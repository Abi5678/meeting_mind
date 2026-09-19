//
//  WaveformBanner.swift
//  Instant Notes
//
// Live waveform for meeting capture: the newest microphone level enters on the right and scrolls left.

import SwiftUI

struct WaveformBanner: View {
    /// Recent levels from 0 to 1, oldest first.
    let levels: [Double]
    let isRecording: Bool

    static let barCount = 60

    var body: some View {
        Canvas { context, size in
            let slot = size.width / CGFloat(Self.barCount)
            let barWidth = max(2, slot * 0.55)
            // Pad the front with silence so a fresh recording starts at the right edge.
            let padded = Array(repeating: 0, count: max(0, Self.barCount - levels.count)) + levels.suffix(Self.barCount)

            for (index, level) in padded.enumerated() {
                let height = max(3, CGFloat(level) * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * slot + (slot - barWidth) / 2,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                // Older bars fade so the eye follows the live edge.
                let age = Double(index) / Double(Self.barCount)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(isRecording ? Color.red.opacity(0.35 + 0.65 * age) : Color.secondary.opacity(0.3))
                )
            }
        }
        .frame(height: 120)
        .animation(.linear(duration: 0.05), value: levels)
        .accessibilityLabel(isRecording ? "Live audio level" : "Audio level")
    }
}

// MARK: - Recording timer display

struct TimerDisplay: View {
    let timeInterval: TimeInterval

    var body: some View {
        Text(formatDuration(timeInterval))
            .font(.system(size: 48, design: .monospaced))
            .monospacedDigit()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
