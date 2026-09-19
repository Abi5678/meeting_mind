//
//  AudioRecorderService.swift
//  MeetingMindKit
//
//  iOS-specific audio recorder using AVFoundation.
// Records in mono AAC m4a at 44.1kHz. Stores files under a UUID-named directory.
//

import Foundation
import AVFoundation
#if os(iOS)
import UIKit
#endif

/// Result of a completed recording.
public struct AudioRecordingResult: Sendable {
    public let url: URL
    public let duration: TimeInterval
    public let startTime: Date
}

/// iOS audio recording service with permission handling, interruptions, and auto-stop on background transition.
@MainActor
public final class AudioRecorderService: NSObject, ObservableObject {
    @Published public var isRecording = false
    @Published public var recordingDuration: TimeInterval = 0
    /// Microphone loudness from 0 (silence) to 1, refreshed about 20 times a second while recording.
    @Published public private(set) var level: Double = 0
    @Published public var error: Error?

    private var audioRecorder: AVAudioRecorder?
    private var meteringTimer: Timer?
    private var recordingStartTime: Date?
    private var lastRecordingURL: URL?
    private let recordingsDirectory: URL

    // MARK: - Initialization

    public init(recordingsDirectory: URL = AudioRecorderService.defaultRecordingsDirectory()) {
        self.recordingsDirectory = recordingsDirectory
        super.init()
        setupFileManager()
        setupAudioSession()
        observeInterruptions()
        observeBackgroundNotifications()
    }

    // MARK: - Recording API

    public func startRecording(name: String = "Recording") -> URL {
        let timestamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let filename = "\(name)_\(timestamp).m4a"
        let url = recordingsDirectory.appending(path: filename)

        do {
            stopRecording() // clean up any previous recording
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            lastRecordingURL = url
            recordingStartTime = .now
            isRecording = true
            recordingDuration = 0
            startTimer()
        } catch {
            self.error = RecordingError.recordingFailed(error.localizedDescription)
        }

        return url
    }

    @discardableResult
    public func stopRecording() -> AudioRecordingResult? {
        guard isRecording else { return nil }

        let url = audioRecorder?.url ?? lastRecordingURL
        let duration = recordingDuration
        let startTime = recordingStartTime ?? .now

        audioRecorder?.stop()
        audioRecorder = nil
        stopTimer()

        isRecording = false
        recordingDuration = 0
        recordingStartTime = nil

        guard let url else { return nil }
        return AudioRecordingResult(url: url, duration: duration, startTime: startTime)
    }

    public func pauseRecording() {
        guard isRecording, audioRecorder?.isRecording == true else { return }
        audioRecorder?.pause()
        stopTimer()
    }

    public func resumeRecording() {
        guard isRecording, audioRecorder?.isRecording == false else { return }
        recordingStartTime = Date().addingTimeInterval(-recordingDuration)
        audioRecorder?.record()
        startTimer()
    }

    /// Request microphone permission asynchronously. Returns true if granted.
    public func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func isRecordingAvailable() -> Bool {
        #if os(iOS)
        return AVAudioSession.sharedInstance().isInputAvailable
        #else
        return false
        #endif
    }

    // MARK: - Private helpers

    private func setupFileManager() {
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
    }

    private func setupAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true, options: [.notifyOthersOnDeactivation])
        #endif
    }

    private func startTimer() {
        stopTimer()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
                if let recorder = self.audioRecorder {
                    recorder.updateMeters()
                    self.level = Self.normalizedLevel(decibels: recorder.averagePower(forChannel: 0))
                }
            }
        }
    }

    private func stopTimer() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        level = 0
    }

    /// Maps average power (-160…0 dBFS) to 0…1. Anything under -50 dB is room noise and reads as
    /// silence; the square root lifts normal speech so the waveform visibly moves.
    nonisolated static func normalizedLevel(decibels: Float) -> Double {
        let floor: Float = -50
        guard decibels.isFinite, decibels > floor else { return 0 }
        return Double(min(1, (decibels - floor) / -floor)).squareRoot()
    }

    public nonisolated static func defaultRecordingsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appending(path: "com.instantnotes.app/Recordings")
    }

    // MARK: - Interruption & background notifications

    private func observeInterruptions() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        #endif
    }

    private func observeBackgroundNotifications() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForeground(_:)),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #endif
    }

    #if os(iOS)
    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // OS is pausing audio — our recorder may be paused by the system too.
            break
        case .ended:
            let rawOptions = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
                try? AVAudioSession.sharedInstance().setActive(true)
                resumeRecording()
            }
        @unknown default:
            break
        }
    }

    @objc private func handleWillEnterForeground(_ notification: Notification) {
        // If we were paused by the OS during background transition, reactivate the session.
        if isRecording {
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }
    #endif

    // MARK: - Error types

    public enum RecordingError: Error, LocalizedError {
        case directoryCreationFailed
        case recordingFailed(String)
        case permissionDenied

        public var errorDescription: String? {
            switch self {
            case .directoryCreationFailed: "Could not create recordings directory."
            case .recordingFailed(let reason): "Recording failed: \(reason)"
            case .permissionDenied: "Microphone permission denied."
            }
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorderService: AVAudioRecorderDelegate {
    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return }
        Task { @MainActor in
            self.error = RecordingError.recordingFailed("Recording failed unexpectedly.")
        }
    }

    public nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        guard let message = error?.localizedDescription else { return }
        Task { @MainActor in
            self.error = RecordingError.recordingFailed(message)
        }
    }
}
