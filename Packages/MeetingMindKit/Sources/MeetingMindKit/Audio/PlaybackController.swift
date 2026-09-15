//
//  PlaybackController.swift
//  MeetingMindKit
//
//  AVAudioPlayer wrapper for audio playback with time tracking.
// Ported from NotabilityClone — identical API, iOS-compatible.
//

import Foundation
import AVFoundation

/// Audio playback controller with seek, play/pause, and real-time current-time reporting.
@MainActor
public final class PlaybackController: NSObject, ObservableObject {
    @Published public var isPlaying = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    @Published public var error: Error?

    private var audioPlayer: AVAudioPlayer?
    private var playbackUpdateTimer: Timer?

    /// Load an audio file for playback. Call before play().
    public func load(url: URL) {
        stop()

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.enableRate = true
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
        } catch {
            self.error = PlaybackError.loadFailed(error.localizedDescription)
        }
    }

    /// Start playback.
    public func play() {
        guard let player = audioPlayer, !isPlaying else { return }
        player.play()
        isPlaying = true
        startUpdateTimer()
    }

    /// Pause playback.
    public func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopUpdateTimer()
    }

    /// Stop playback and reset time to zero.
    public func stop() {
        audioPlayer?.stop()
        isPlaying = false
        currentTime = 0
        stopUpdateTimer()
    }

    /// Seek to a specific time in the loaded audio.
    public func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        player.currentTime = time
        currentTime = time
        if isPlaying {
            stopUpdateTimer()
            startUpdateTimer()
        }
    }

    // MARK: - Internal

    private func startUpdateTimer() {
        stopUpdateTimer()
        playbackUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopUpdateTimer() {
        playbackUpdateTimer?.invalidate()
        playbackUpdateTimer = nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension PlaybackController: AVAudioPlayerDelegate {
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.stopUpdateTimer()
            if flag {
                self.currentTime = self.duration
            }
        }
    }

    public nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard let message = error?.localizedDescription else { return }
        Task { @MainActor in
            self.error = PlaybackError.decodeFailed(message)
        }
    }
}

// MARK: - Error types

public enum PlaybackError: LocalizedError {
    case loadFailed(String)
    case decodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let reason): "Could not load audio: \(reason)"
        case .decodeFailed(let reason): "Audio decode error: \(reason)"
        }
    }
}
