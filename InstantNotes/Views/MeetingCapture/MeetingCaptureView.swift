//
//  MeetingCaptureView.swift
//  Instant Notes
//
// Records a meeting, transcribes it with Apple Speech, summarizes it on the device with Apple
// Intelligence, and saves it as a note. An audio or video file, or a YouTube video's captions,
// go through the same steps in place of the microphone.

import SwiftUI
import SwiftData
import PhotosUI
import CoreTransferable
import MeetingMindKit

/// Where the meeting comes from.
enum CaptureSource: Equatable {
    case microphone
    /// An audio or video file picked in Files (or Finder on the Mac).
    case file(URL)
    /// A video from the photo library.
    case video(PhotosPickerItem)
    /// A YouTube link, as the user pasted it.
    case youTube(String)
}

struct MeetingCaptureView: View {
    var source: CaptureSource = .microphone
    /// Called with the saved note so the list can open it.
    var onSave: (Note) -> Void = { _ in }

    @StateObject private var viewModel = MeetingSession()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var confirmingDiscard = false

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .recording: recorder
            case .preparing, .transcribing, .transcribingOnDevice, .analyzing: working
            case .soundsLikeMusic: musicWarning
            case .done: results
            case let .failed(message): failure(message)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if viewModel.hasCapture { confirmingDiscard = true } else { dismiss() }
                }
                .confirmationDialog("Discard this meeting?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { dismiss() }
                    if !viewModel.transcript.isEmpty {
                        Button("Save as note") { saveAndDismiss() }
                    }
                    Button(viewModel.phase == .recording ? "Keep recording" : "Keep", role: .cancel) {}
                } message: {
                    Text("The audio and anything transcribed so far will be deleted.")
                }
            }
        }
        .interactiveDismissDisabled(viewModel.phase != .idle)
        .onAppear { if source != .microphone, viewModel.phase == .idle { viewModel.importMeeting(from: source) } }
        .onDisappear { viewModel.cancel() }
    }

    private var title: String {
        switch source {
        case .microphone: "Meeting"
        case .file, .video: "Import"
        case .youTube: "YouTube"
        }
    }

    private func saveAndDismiss() {
        let note = viewModel.save(in: modelContext)
        dismiss()
        onSave(note)
    }

    private var recorder: some View {
        let isRecording = viewModel.phase == .recording
        return VStack(spacing: 24) {
            Spacer()

            WaveformBanner(levels: viewModel.levels, isRecording: isRecording && !viewModel.isPaused)
                .padding(.horizontal, 24)

            TimerDisplay(timeInterval: viewModel.recordingDuration)
                .font(.system(size: 64, design: .monospaced))

            if viewModel.isPaused {
                Button { viewModel.resumeRecording() } label: {
                    Label(viewModel.resumeFailed ? "Microphone still in use — tap to try again" : "Recording paused — tap to resume",
                          systemImage: "play.circle.fill")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }

            if let warning = viewModel.speechWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.4)) {
                    viewModel.toggleRecording()
                }
            } label: {
                Circle()
                    .fill(isRecording ? Color.red : Color.secondary.opacity(0.2))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.title2)
                            .foregroundStyle(isRecording ? .white : .primary)
                    )
            }
            .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")

            Text(isRecording ? "Tap to stop and summarize" : "Tap to start recording")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var working: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(viewModel.phase.description)
                .font(.headline)
            Text("Keep the app open until this finishes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }

    private var results: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let analysis = viewModel.analysis {
                    MeetingAnalysisView(analysis: analysis)
                } else if let error = viewModel.analysisError {
                    VStack(spacing: 10) {
                        Label("No summary yet", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try summary again") { viewModel.summarize() }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                DisclosureGroup("Transcript") {
                    Text(viewModel.transcript)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                .padding(16)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    saveAndDismiss()
                } label: {
                    Label("Save as note", systemImage: "note.text.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
    }

    /// An imported song would come out as a meeting summary of its lyrics, so ask first.
    private var musicWarning: some View {
        let isYouTube = if case .youTube = source { true } else { false }
        return ContentUnavailableView {
            Label("This sounds like music", systemImage: "music.note")
        } description: {
            Text(isYouTube
                 ? "Its captions read like song lyrics. Recapped summarizes people talking, so the notes may not be useful."
                 : "Recapped summarizes people talking, and this sounds more like a song, so the notes may not be useful.")
        } actions: {
            Button(isYouTube ? "Summarize anyway" : "Transcribe anyway") { viewModel.continueAfterMusicWarning() }
                .buttonStyle(.borderedProminent)
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
        }
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't finish", systemImage: "mic.slash")
        } description: {
            Text(message)
        } actions: {
            if viewModel.recording != nil {
                // The audio is still on disk: transcribe it again, or keep it as a note without a summary.
                Button("Try again") { viewModel.retryTranscription() }
                    .buttonStyle(.borderedProminent)
                Button(viewModel.transcript.isEmpty ? "Save audio only" : "Save audio and partial transcript") {
                    saveAndDismiss()
                }
                .buttonStyle(.bordered)
                if source == .microphone { Button("Record again") { viewModel.reset() } }
            } else if source == .microphone {
                Button("Record again") { viewModel.reset() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// A video from the photo library, copied out so it can be read after the picker lets go of it.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appending(path: "\(UUID())-\(received.file.lastPathComponent)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}
