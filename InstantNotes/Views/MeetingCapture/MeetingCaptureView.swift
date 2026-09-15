//
//  MeetingCaptureView.swift
//  Instant Notes
//
// Records a meeting, transcribes it with Apple Speech, summarizes it with Gemini, and saves it as a note.

import SwiftUI
import SwiftData
import MeetingMindKit

struct MeetingCaptureView: View {
    /// Called with the saved note so the list can open it.
    var onSave: (Note) -> Void = { _ in }

    @StateObject private var viewModel = MeetingCaptureViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .recording: recorder
            case .transcribing, .analyzing: working
            case .done: results
            case let .failed(message): failure(message)
            }
        }
        .navigationTitle("Meeting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .interactiveDismissDisabled(viewModel.phase != .idle)
        .onDisappear { viewModel.cancel() }
    }

    private var recorder: some View {
        let isRecording = viewModel.phase == .recording
        return VStack(spacing: 24) {
            Spacer()

            WaveformBanner(isRecording: isRecording)
                .padding(.horizontal, 32)

            TimerDisplay(timeInterval: viewModel.recordingDuration)
                .font(.system(size: 64, design: .monospaced))

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
                    let note = viewModel.save(in: modelContext)
                    dismiss()
                    onSave(note)
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

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't finish", systemImage: "mic.slash")
        } description: {
            Text(message)
        } actions: {
            Button("Record again") { viewModel.reset() }
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class MeetingCaptureViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing(window: Int, total: Int)
        case analyzing
        case done
        case failed(String)

        var description: String {
            switch self {
            case let .transcribing(window, total) where total > 1: "Transcribing part \(window) of \(total)…"
            case .transcribing: "Transcribing…"
            case .analyzing: "Summarizing with Gemini…"
            default: ""
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var transcript = ""
    @Published private(set) var analysis: MeetingAnalysis?
    /// Set when transcription worked but Gemini did not; the transcript can still be saved.
    @Published private(set) var analysisError: String?

    private var timer: Timer?
    private var work: Task<Void, Never>?
    private var recording: AudioRecordingResult?
    private let recorderService = AudioRecorderService()

    func toggleRecording() {
        if phase == .recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        work = Task {
            guard await recorderService.requestPermission() else {
                phase = .failed("Microphone access is off. Turn it on for Instant Notes in Settings.")
                return
            }
            // Ask now, not after an hour-long meeting has been recorded.
            guard await SpeechFileTranscriber.requestAuthorization() else {
                phase = .failed(SpeechFileTranscriber.Failure.notAuthorized.localizedDescription)
                return
            }

            recorderService.startRecording(name: "Meeting")
            guard recorderService.isRecording else {
                phase = .failed(recorderService.error?.localizedDescription ?? "Recording couldn't start.")
                return
            }
            phase = .recording
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.recordingDuration = self.recorderService.recordingDuration
                }
            }
        }
    }

    func stopRecording() {
        timer?.invalidate()
        timer = nil
        recordingDuration = recorderService.recordingDuration

        guard let result = recorderService.stopRecording() else {
            phase = .failed("The recording was lost.")
            return
        }
        recording = result
        work = Task { await transcribe(result.url) }
    }

    func summarize() {
        work = Task { await analyze() }
    }

    func reset() {
        cancel()
        phase = .idle
        recordingDuration = 0
        transcript = ""
        analysis = nil
        analysisError = nil
        recording = nil
    }

    /// Stops everything when the screen goes away mid-recording or mid-processing.
    func cancel() {
        work?.cancel()
        timer?.invalidate()
        timer = nil
        recorderService.stopRecording()
    }

    private func transcribe(_ url: URL) async {
        phase = .transcribing(window: 0, total: 0)
        do {
            #if DEBUG
            // iOS 26.4+ simulators can't run SFSpeechRecognizer (kLSRErrorDomain 300); launch with
            // `-debugTranscript "…"` to exercise the rest of the pipeline there.
            if let debugTranscript = UserDefaults.standard.string(forKey: "debugTranscript") {
                transcript = debugTranscript
                await analyze()
                return
            }
            #endif
            transcript = try await SpeechFileTranscriber().transcribe(fileAt: url) { [weak self] window, total in
                await self?.setPhase(.transcribing(window: window, total: total))
            }
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .failed("No speech was heard in that recording.")
            return
        }
        await analyze()
    }

    private func analyze() async {
        analysisError = nil
        guard let key = GeminiKey.current else {
            analysisError = "Add a Gemini API key in Settings to get a summary. You can still save the transcript."
            phase = .done
            return
        }

        phase = .analyzing
        let model = UserDefaults.standard.string(forKey: "gemini_model") ?? "gemini-3-flash-preview"
        do {
            analysis = try await GeminiClient(apiKey: key, configuration: .init(model: model)).analyze(transcript: transcript)
        } catch {
            guard !Task.isCancelled else { return }
            analysisError = error.localizedDescription
        }
        phase = .done
    }

    private func setPhase(_ phase: Phase) {
        self.phase = phase
    }

    func save(in context: ModelContext) -> Note {
        let startedAt = recording?.startTime ?? .now
        let note = Note(title: "Meeting \(startedAt.formatted(date: .abbreviated, time: .shortened))", summary: analysis?.summary)
        note.blockDocument = BlockDocument(blocks: MeetingNoteBuilder.blocks(analysis: analysis, transcript: transcript))
        context.insert(note)

        if let recording {
            // File name only: the app container path changes between installs.
            let saved = Recording(name: note.title, filePath: recording.url.lastPathComponent,
                                  duration: recording.duration, createdAt: startedAt, isTranscribed: true)
            let artifact = MeetingArtifact(recordingId: saved.id, status: MeetingProcessingStatus.ready.rawValue,
                                           summary: analysis?.summary, fullTranscript: transcript)
            artifact.recording = saved
            note.recordings.append(saved)
            note.meetingArtifact = artifact
        }
        return note
    }
}
