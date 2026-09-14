//
//  WaveformBanner.swift
//  Instant Notes
//
// Animated waveform visualization for meeting capture.
// Uses animated bars as a placeholder until real waveform data is available.

import SwiftUI

struct WaveformBanner: View {
    let isRecording: Bool
    private let barCount = 48

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    waveformBar(index: i, containerWidth: geo.size.width)
                }
            }
            .frame(height: 48)
        }
    }

    @ViewBuilder
    private func waveformBar(index: Int, containerWidth: CGFloat) -> some View {
        let centerOffset = abs(Double(index) - Double(barCount - 1) / 2.0) / (Double(barCount) / 2.0)
        let baseHeight = max(4, 40 * (1 - centerOffset))

        Rectangle()
            .fill(Color.accentColor.opacity(isRecording ? 0.6 : 0.3))
            .frame(width: 3, height: isRecording ? animatedBarHeight(base: baseHeight, index: index) : baseHeight * 0.5)
            .clipShape(RoundedRectangle(cornerRadius: 1.5))
    }

    private func animatedBarHeight(base: CGFloat, index: Int) -> CGFloat {
        // Generate a sine-wave pattern offset by index for organic appearance
        let t = Double(Date().timeIntervalSinceReferenceDate)
        return base * (0.3 + 0.7 * (sin(t * 2.0 + Double(index) * 0.3).magnitude + 0.5))
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
