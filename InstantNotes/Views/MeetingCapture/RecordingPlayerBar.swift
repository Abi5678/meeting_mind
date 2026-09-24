//
//  RecordingPlayerBar.swift
//  Instant Notes
//
// Plays back the audio a meeting note was made from.

import SwiftUI
import AVFoundation
import MeetingMindKit

struct RecordingPlayerBar: View {
    let recording: Recording
    /// Seconds to start playing from as soon as the bar appears (a search hit in the transcript).
    var startAt: TimeInterval? = nil
    @StateObject private var player = PlaybackController()

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if player.isPlaying { player.pause() } else { play() }
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(player.error != nil)
            .accessibilityLabel(player.isPlaying ? "Pause recording" : "Play recording")

            if player.error != nil {
                Text("Recording file not found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Slider(
                    value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                    in: 0...max(player.duration, 0.1)
                )
                .accessibilityLabel("Playback position")

                Text("\(timestamp(player.currentTime)) / \(timestamp(player.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onAppear {
            // Only the file name is stored: the app container path changes between installs.
            player.load(url: AudioRecorderService.defaultRecordingsDirectory().appending(path: recording.filePath))
            if let startAt, player.error == nil {
                // A second early, so the words searched for aren't clipped.
                player.seek(to: max(0, startAt - 1))
                play()
            }
        }
        .onDisappear { player.stop() }
    }

    private func play() {
        // Recording leaves the session in play-and-record; playback should ignore the silent switch like any media app.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        if player.currentTime >= player.duration { player.seek(to: 0) }
        player.play()
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
