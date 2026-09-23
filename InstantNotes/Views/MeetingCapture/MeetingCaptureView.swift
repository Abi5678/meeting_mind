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
    @State private var confirmingDiscard = false
    @State private var showKeySettings = false

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
        .onDisappear { viewModel.cancel() }
        .sheet(isPresented: $showKeySettings, onDismiss: {
            if GeminiKey.current != nil { viewModel.summarize() }
        }) {
            NavigationStack { AISettingsView() }
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
                        if viewModel.needsAPIKey {
                            // Retrying can't help without a working key; the summary reruns when settings close.
                            Button("Add API key") { showKeySettings = true }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Try summary again") { viewModel.summarize() }
                                .buttonStyle(.bordered)
                        }
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
                Button("Record again") { viewModel.reset() }
            } else {
                Button("Record again") { viewModel.reset() }
                    .buttonStyle(.borderedProminent)
            }
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
    /// An interruption (a call, Siri, an alarm) is holding the recording until it resumes.
    @Published private(set) var isPaused = false
    /// The last resume found the microphone still taken.
    @Published private(set) var resumeFailed = false
    /// Shown while recording when speech recognition already looks unavailable.
    @Published private(set) var speechWarning: String?
    /// Rolling microphone levels for the waveform, oldest first.
    @Published private(set) var levels: [Double] = []
    @Published private(set) var transcript = ""
    @Published private(set) var analysis: MeetingAnalysis?
    /// Set when transcription worked but Gemini did not; the transcript can still be saved.
    @Published private(set) var analysisError: String?
    /// The summary failed for want of a working Gemini key, so the results card offers to add one.
    @Published private(set) var needsAPIKey = false
    /// The finished audio. Kept through a failed transcription so it can be retried or saved.
    @Published private(set) var recording: AudioRecordingResult?

    private var timer: Timer?
    private var work: Task<Void, Never>?
    /// Once saved, the audio belongs to a note and must not be deleted on the way out.
    private var isSaved = false
    private let recorderService = AudioRecorderService()

    /// Whether Cancel would throw away audio or a transcript.
    var hasCapture: Bool { phase == .recording || recording != nil }

    /// iOS 26.4+ simulators can't run SFSpeechRecognizer (kLSRErrorDomain 300); launch with
    /// `-debugTranscript "…"` to exercise the rest of the pipeline there.
    private var debugTranscript: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "debugTranscript")
        #else
        return nil
        #endif
    }

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
            // Warn before the meeting, not after it. Recording still goes ahead: the audio can be saved.
            if debugTranscript == nil, !SpeechFileTranscriber().isAvailable {
                speechWarning = "Speech recognition isn't available right now (offline, or this language isn't supported), so this meeting may not transcribe. You'll still be able to save the audio."
            }

            recorderService.startRecording(name: "Meeting")
            guard recorderService.isRecording else {
                phase = .failed(recorderService.error?.localizedDescription ?? "Recording couldn't start.")
                return
            }
            phase = .recording
            levels = []
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.phase == .recording else { return }
                    if let error = self.recorderService.error {
                        self.recordingStopped(by: error)
                        return
                    }
                    self.isPaused = self.recorderService.isPaused
                    if !self.isPaused { self.resumeFailed = false }
                    self.recordingDuration = self.recorderService.recordingDuration
                    // Hold the waveform still while paused rather than scrolling silence past.
                    guard !self.isPaused else { return }
                    self.levels = (self.levels + [self.recorderService.level]).suffix(WaveformBanner.barCount)
                }
            }
        }
    }

    func resumeRecording() {
        resumeFailed = !recorderService.resumeRecording()
        isPaused = recorderService.isPaused
    }

    /// The recorder gave up on its own (an encoding error, the input went away): keep what it captured.
    private func recordingStopped(by error: Error) {
        timer?.invalidate()
        timer = nil
        recording = recorderService.stopRecording()
        phase = .failed(error.localizedDescription)
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

    /// Transcribes the same audio again, e.g. once the network is back.
    func retryTranscription() {
        guard let recording else { return }
        transcript = ""
        work = Task { await transcribe(recording.url) }
    }

    func reset() {
        cancel()
        phase = .idle
        recordingDuration = 0
        isPaused = false
        resumeFailed = false
        speechWarning = nil
        levels = []
        transcript = ""
        analysis = nil
        analysisError = nil
        needsAPIKey = false
        recording = nil
    }

    /// Stops everything when the screen goes away mid-recording or mid-processing. Audio that never
    /// made it into a note is deleted, since nothing points at it; a saved note keeps its file.
    func cancel() {
        work?.cancel()
        timer?.invalidate()
        timer = nil
        if let unfinished = recorderService.stopRecording() { recording = unfinished }
        if !isSaved, let url = recording?.url {
            try? FileManager.default.removeItem(at: url)
            recording = nil
        }
    }

    private func transcribe(_ url: URL) async {
        phase = .transcribing(window: 0, total: 0)
        do {
            if let debugTranscript {
                transcript = debugTranscript
                await analyze()
                return
            }
            transcript = try await SpeechFileTranscriber().transcribe(fileAt: url) { [weak self] window, total in
                await self?.setPhase(.transcribing(window: window, total: total))
            }
        } catch is CancellationError {
            return
        } catch {
            // Keep the parts that did transcribe so saving from the failure screen holds on to them.
            if case let SpeechFileTranscriber.Failure.incomplete(partial, _, _) = error { transcript = partial }
            phase = .failed(Self.transcriptionFailureMessage(for: error))
            return
        }

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .failed("No speech was heard in that recording.")
            return
        }
        await analyze()
    }

    /// Apple reports a missing speech model as "Failed to initialize recognizer", which says nothing
    /// about the cause, so the two cases that produce it are named instead.
    static func transcriptionFailureMessage(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == "kLSRErrorDomain", nsError.code == 300 else {
            return error.localizedDescription
        }
        #if targetEnvironment(simulator)
        return "The iOS Simulator ships no speech models, so recordings can't be transcribed here. Run on a device to transcribe."
        #else
        return "Speech recognition couldn't load its language model. Check the language is downloaded in Settings."
        #endif
    }

    private func analyze() async {
        analysisError = nil
        needsAPIKey = false
        guard let key = GeminiKey.current else {
            analysisError = "Add a Gemini API key (… menu → AI) to get a summary. You can still save the transcript."
            needsAPIKey = true
            phase = .done
            return
        }

        phase = .analyzing
        let model = UserDefaults.standard.string(forKey: "gemini_model") ?? "gemini-3.8-flash"
        do {
            analysis = try await GeminiClient(apiKey: key, configuration: .init(model: model)).analyze(transcript: transcript)
        } catch {
            guard !Task.isCancelled else { return }
            analysisError = error.localizedDescription
            // 400–403 is how Gemini rejects a malformed, revoked or unauthorized key.
            if case GeminiError.http(status: 400..<404, _) = error { needsAPIKey = true }
        }
        phase = .done
    }

    private func setPhase(_ phase: Phase) {
        self.phase = phase
    }

    /// Topic-first title: summary/transcript gist, not a raw timestamp dump.
    private func topicTitle(startedAt: Date, analysis: MeetingAnalysis?, transcript: String) -> String {
        func gist(_ text: String) -> String? {
            let terminators = CharacterSet(charactersIn: ".!?\n")
            let sentence = text.components(separatedBy: terminators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? ""
            let words = sentence.split(separator: " ").prefix(8)
            return words.count >= 3 ? words.joined(separator: " ") : nil
        }
        if let analysis, let g = gist(analysis.summary) { return g }
        if let g = gist(transcript) { return g }
        return "Meeting notes · \(startedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    func save(in context: ModelContext) -> Note {
        isSaved = true
        let startedAt = recording?.startTime ?? .now
        let note = Note(title: topicTitle(startedAt: startedAt, analysis: analysis, transcript: transcript), summary: analysis?.summary)
        note.blockDocument = BlockDocument(blocks: MeetingNoteBuilder.blocks(analysis: analysis, transcript: transcript))
        context.insert(note)

        if let recording {
            // Saved from the failure screen, the transcript is missing or partial.
            let transcribed: Bool = if case .failed = phase { false } else { true }
            // File name only: the app container path changes between installs.
            let saved = Recording(name: note.title, filePath: recording.url.lastPathComponent,
                                  duration: recording.duration, createdAt: startedAt, isTranscribed: transcribed)
            let artifact = MeetingArtifact(recordingId: saved.id,
                                           status: (transcribed ? MeetingProcessingStatus.ready : .failed).rawValue,
                                           summary: analysis?.summary, fullTranscript: transcript)
            artifact.recording = saved
            note.recordings.append(saved)
            note.meetingArtifact = artifact
        }
        return note
    }
}
