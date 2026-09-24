//
//  RecordingPlayerBar.swift
//  Instant Notes
//
// Plays back the audio a meeting note was made from.

import SwiftUI
import AVFoundation
import MeetingMindKit

struct RecordingPlayerBar: View {
    /// Owned by the editor, so its blocks and ink can play from their moment too.
    @ObservedObject var player: PlaybackController
    /// Given when the note has ink written while recording: tapping a stroke then plays from it.
    var isReplaying: Binding<Bool>? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if player.isPlaying { player.pause() } else { Self.play(player) }
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
            if let isReplaying {
                Button { isReplaying.wrappedValue.toggle() } label: {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(isReplaying.wrappedValue ? Color.white : Color.accentColor)
                        .background(Color.accentColor.opacity(isReplaying.wrappedValue ? 1 : 0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Replay ink")
                .accessibilityValue(isReplaying.wrappedValue ? "On: tap ink to hear it" : "Off")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Loads `recording` into `player`. Only the file name is stored: the app container path
    /// changes between installs. A recording synced from another device gets its file here.
    static func load(_ recording: Recording, into player: PlaybackController) {
        player.error = nil
        player.load(url: CloudSync.audioURL(for: recording))
    }

    static func play(_ player: PlaybackController) {
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
