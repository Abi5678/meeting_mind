//
//  NoteRecorder.swift
//  Instant Notes
//
// Records audio inside a note: one recording at a time for the whole app, so it keeps going
// when you leave the note. When it's done, the summary and transcript go at the end of the note.

import SwiftUI
import Combine
import MeetingMindKit

@MainActor
final class NoteRecorder: ObservableObject {
    /// The recording in progress, or being turned into notes.
    @Published private(set) var session: MeetingCaptureViewModel?
    /// The note it belongs to.
    @Published private(set) var noteID: UUID?
    private var note: Note?
    private var watch: AnyCancellable?

    func isRecording(into note: Note) -> Bool { session != nil && noteID == note.id }

    func start(for note: Note) {
        guard session == nil else { return }
        let session = MeetingCaptureViewModel()
        self.session = session
        self.note = note
        noteID = note.id
        // `$phase` sends before the value is set, so finish on the next turn.
        watch = session.$phase.sink { [weak self] phase in
            if phase == .done { Task { @MainActor in self?.finish() } }
        }
        session.startRecording()
    }

    /// Where the recording is now, for stamping what's written in `note`.
    func mark(for note: Note) -> AudioMark? {
        isRecording(into: note) ? session?.currentMark : nil
    }

    /// Adds what was captured to the note: the summary and transcript, or after a failed
    /// transcription, just the audio.
    func finish() {
        guard let session, let note, let context = note.modelContext else { return discard() }
        session.save(in: context, into: note)
        try? context.save()
        clear()
    }

    /// Stops and throws away the recording.
    func discard() {
        session?.cancel()
        clear()
    }

    private func clear() {
        watch = nil
        session = nil
        note = nil
        noteID = nil
    }
}

/// Shown over the bottom of a note while it's recording, and while the recording is processed.
struct NoteRecordingBanner: View {
    @ObservedObject var session: MeetingCaptureViewModel
    @EnvironmentObject private var recorder: NoteRecorder

    var body: some View {
        Group {
            switch session.phase {
            case .recording: recording
            case let .failed(message): failure(message)
            default: working
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var recording: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.isPaused ? Color.orange : Color.red)
                .frame(width: 10, height: 10)
            Text(timestamp(session.recordingDuration))
                .font(.subheadline.monospacedDigit().weight(.semibold))
            if session.isPaused {
                Text(session.resumeFailed ? "Microphone in use" : "Paused")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if session.isPaused { session.resumeRecording() } else { session.pauseRecording() }
            } label: {
                Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 36, height: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityLabel(session.isPaused ? "Resume recording" : "Pause recording")
            Button("Stop") { session.stopRecording() }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.red)
        }
    }

    private var working: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var status: String {
        switch session.phase {
        case .idle: "Starting…"
        case let .preparing(text): text
        case let .transcribing(window, total) where total > 1: "Transcribing \(window) of \(total)…"
        case .transcribing: "Transcribing…"
        case let .transcribingOnDevice(percent): "Transcribing… \(percent)%"
        case .analyzing: "Summarizing…"
        default: "Adding to the note…"
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .lineLimit(3)
            HStack {
                if session.recording != nil {
                    Button("Retry") { session.retryTranscription() }
                    Button("Keep audio") { recorder.finish() }
                }
                Spacer()
                Button(session.recording != nil ? "Discard" : "Dismiss", role: .destructive) { recorder.discard() }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}
