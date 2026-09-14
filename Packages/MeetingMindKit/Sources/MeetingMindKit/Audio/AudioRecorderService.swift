//
//  AudioRecorderService.swift
//  MeetingMindKit
//
//  iOS-specific audio recorder using AVFoundation.
// Records in mono AAC m4a at 44.1kHz. Stores files under a UUID-named directory.
//

import Foundation
import AVFoundation

/// Result of a completed recording.
public struct AudioRecordingResult {
    public let url: URL
    public let duration: TimeInterval
    public let startTime: Date
}

/// iOS audio recording service with permission handling, interruptions, and auto-stop on background transition.
@MainActor
public final class AudioRecorderService: ObservableObject {
    @Published public var isRecording = false
    @Published public var recordingDuration: TimeInterval = 0
    @Published public var error: Error?

    private var audioRecorder: AVAudioRecorder?
    private var meteringTimer: Timer?
    private var recordingStartTime: Date?
    private var lastRecordingURL: URL?
    private let recordingsDirectory: URL

    // MARK: - Initialization

    public init(recordingsDirectory: URL = Self.defaultRecordingsDirectory()) {
        self.recordingsDirectory = recordingsDirectory
        setupFileManager()
        setupAudioSession()
        observeInterruptions()
        observeBackgroundNotifications()
    }

    deinit {
        stopRecording()
    }

    // MARK: - Recording API

    public func startRecording(name: String = "Recording") -> URL {
        let timestamp = Date().formatted(date: .numeric, time: .standard)
        let filename = "\(name)_\(timestamp).m4a"
        let url = recordingsDirectory.appending(path: filename)

        do {
            stopRecording() // clean up any previous recording
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
            guard FileManager.default.isReadableFile(atPath: recordingsDirectory.path) || FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true) else {
                throw RecordingError.directoryCreationFailed
            }

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

    public func stopRecording() -> AudioRecordingResult? {
        guard isRecording else { return nil }

        let url = audioRecorder?.url ?? lastRecordingURL
        let duration = recordingDuration

        audioRecorder?.stop()
        audioRecorder = nil
        stopTimer()

        isRecording = false
        recordingDuration = 0
        recordingStartTime = nil

        guard let url else { return nil }
        return AudioRecordingResult(url: url, duration: duration, startTime: lastRecordingURL == url ? recordingStartTime ?? .now : .now)
    }

    public func pauseRecording() {
        guard isRecording, audioRecorder?.isRecording == true else { return }
        audioRecorder?.pause()
    }

    public func resumeRecording() {
        guard isRecording, audioRecorder?.isRecording == false else { return }
        recordingStartTime = Date().addingTimeInterval(-recordingDuration)
        audioRecorder?.record()
        startTimer()
    }

    /// Request microphone permission asynchronously. Returns true if granted.
    public func requestPermission() async -> Bool {
        let (granted, error) = await withCheckedContinuation { cont in
            AVAudioApplication.shared.requestRecordPermission { granted in
                cont.resume(returning: (granted, nil))
            }
        }
        return granted
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
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        } catch {}
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true, options: [.notifyOthersOnDeactivation])
    }

    private func startTimer() {
        stopTimer()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let startTime = self.recordingStartTime else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopTimer() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    private static func defaultRecordingsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appending(path: "com.instantnotes.app/Recordings")
    }

    // MARK: - Interruption & background notifications

    private func observeInterruptions() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruitionNotification,
            object: AVAudioSession.sharedInstance()
        )
        #endif
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // OS is pausing audio — our recorder may be paused by the system too.
            // We keep state; if we called pause() this would be redundant.
            break
        case .ended:
            let options = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if options.rawValue == AVAudioSession.InterruptionOptions.shouldResume.rawValue {
                Task { @MainActor in
                    try? await AVAudioSession.sharedInstance().setActive(true)
                    resumeRecording()
                }
            }
        @unknown default:
            break
        }
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

    @objc private func handleWillEnterForeground(_ notification: Notification) {
        // If we were paused by the OS during background transition, resume if still marked as recording.
        if isRecording {
            Task { @MainActor in
                try? await AVAudioSession.sharedInstance().setActive(true)
            }
        }
    }

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

// MARK: - AVAudioRecorderDelegate conformance — moved to separate extension for clarity

@MainActor
extension AudioRecorderService: AVAudioRecorderDelegate {
    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            self.error = RecordingError.recordingFailed("Recording failed unexpectedly.")
        }
    }

    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        guard let error else { return }
        self.error = RecordingError.recordingFailed(error.localizedDescription)
    }
}
