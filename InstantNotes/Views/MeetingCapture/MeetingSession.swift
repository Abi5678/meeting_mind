//
//  MeetingSession.swift
//  Instant Notes
//
// One meeting from capture to note: records (or imports), transcribes, summarizes on the device,
// and saves. The quick-record sheet and recording inside a note both drive it.

import SwiftUI
import SwiftData
import PhotosUI
import PencilKit
import MeetingMindKit

@MainActor
final class MeetingSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        /// Bringing in a file or fetching captions; the text says which.
        case preparing(String)
        /// An import that sounds like a song; waits for the user to carry on or close.
        case soundsLikeMusic
        case transcribing(window: Int, total: Int)
        case transcribingOnDevice(percent: Int)
        case analyzing
        case done
        case failed(String)

        var description: String {
            switch self {
            case let .transcribing(window, total) where total > 1: "Transcribing part \(window) of \(total)…"
            case .transcribing: "Transcribing…"
            case let .transcribingOnDevice(percent): "Transcribing on this device… \(percent)%"
            case .analyzing: "Summarizing on this device…"
            case let .preparing(text): text
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
    /// The transcript with timings, when the on-device model made it; saved so search can seek.
    private var pieces: [TranscriptPiece] = []
    @Published private(set) var analysis: MeetingAnalysis?
    /// Set when transcription worked but the summary did not; the transcript can still be saved.
    @Published private(set) var analysisError: String?
    /// The finished audio. Kept through a failed transcription so it can be retried or saved.
    @Published private(set) var recording: AudioRecordingResult?
    /// Set for a YouTube video: its captions stand in for a recording.
    private var video: YouTubeCaptions.Video?

    private var timer: Timer?
    private var work: Task<Void, Never>?
    /// Once saved, the audio belongs to a note and must not be deleted on the way out.
    private var isSaved = false
    private let recorderService = AudioRecorderService()
    /// The saved Recording's id, known from the start so blocks written meanwhile can point at it.
    private(set) var recordingID = UUID()
    /// When the recorder started and each time it resumed, so ink can be matched to the audio.
    private var clockSpans: [AudioClock.Span] = []

    /// Whether Cancel would throw away audio or a transcript.
    var hasCapture: Bool { phase == .recording || recording != nil || video != nil }

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
                phase = .failed("Microphone access is off. Turn it on for Recapped in Settings.")
                return
            }
            // Ask now, not after an hour-long meeting has been recorded.
            guard await SpeechFileTranscriber.requestAuthorization() else {
                phase = .failed(SpeechFileTranscriber.Failure.notAuthorized.localizedDescription)
                return
            }
            // Fetch Apple's speech model while the meeting runs, so it's ready when it ends.
            if #available(iOS 26, *), OnDeviceTranscriber.isAvailable {
                Task.detached(priority: .utility) { try? await OnDeviceTranscriber().prepare() }
            }
            // Warn before the meeting, not after it. Recording still goes ahead: the audio can be saved.
            if debugTranscript == nil, !Self.onDeviceSpeechAvailable, !SpeechFileTranscriber().isAvailable {
                speechWarning = "Speech recognition isn't available right now (offline, or this language isn't supported), so this meeting may not transcribe. You'll still be able to save the audio."
            }

            recorderService.startRecording(name: "Meeting")
            guard recorderService.isRecording else {
                phase = .failed(recorderService.error?.localizedDescription ?? "Recording couldn't start.")
                return
            }
            phase = .recording
            levels = []
            recordingID = UUID()
            clockSpans = [.init(wallStart: .now, fileOffset: 0)]
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.phase == .recording else { return }
                    if let error = self.recorderService.error {
                        self.recordingStopped(by: error)
                        return
                    }
                    // Interruptions resume on their own, so resumes are noticed here rather than in resumeRecording().
                    if self.isPaused, !self.recorderService.isPaused {
                        self.clockSpans.append(.init(wallStart: .now, fileOffset: self.recorderService.recordingDuration))
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

    /// Brings in a file, a library video or a YouTube video's captions, then carries on exactly as
    /// a recording would once it stops.
    func importMeeting(from source: CaptureSource) {
        work = Task {
            do {
                switch source {
                case .microphone:
                    return
                case let .file(url):
                    phase = .preparing("Importing…")
                    recording = try await MediaImporter.importMedia(from: url)
                case let .video(item):
                    phase = .preparing("Importing video…")
                    guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                        throw MediaImporter.Failure.unreadable
                    }
                    defer { try? FileManager.default.removeItem(at: movie.url) }
                    recording = try await MediaImporter.importMedia(from: movie.url)
                case let .youTube(link):
                    phase = .preparing("Getting captions from YouTube…")
                    let video = try await YouTubeCaptions.fetch(link)
                    self.video = video
                    pieces = video.pieces
                    transcript = TranscriptPiece.joined(video.pieces)
                    if MusicCheck.captionsLookLikeSong(video.pieces) {
                        phase = .soundsLikeMusic
                    } else {
                        await analyze()
                    }
                    return
                }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
                return
            }
            guard let recording else { return }
            phase = .preparing("Checking the audio…")
            let url = recording.url
            let isMusic = await Task.detached(priority: .userInitiated) { (try? MusicCheck.soundsLikeMusic(fileAt: url)) ?? false }.value
            guard !Task.isCancelled else { return }
            if isMusic {
                phase = .soundsLikeMusic
            } else {
                await transcribeImport(recording.url)
            }
        }
    }

    /// Carries on past the music warning: a YouTube video to its summary, a file to transcription.
    func continueAfterMusicWarning() {
        work = Task {
            if video != nil {
                await analyze()
            } else if let recording {
                await transcribeImport(recording.url)
            }
        }
    }

    private func transcribeImport(_ url: URL) async {
        guard await SpeechFileTranscriber.requestAuthorization() else {
            phase = .failed(SpeechFileTranscriber.Failure.notAuthorized.localizedDescription)
            return
        }
        await transcribe(url)
    }

    /// Where the recording is now, for stamping what's written meanwhile; nil when not recording.
    var currentMark: AudioMark? {
        phase == .recording ? AudioMark(recordingID: recordingID, time: recorderService.recordingDuration) : nil
    }

    func pauseRecording() {
        recorderService.pauseRecording()
        isPaused = recorderService.isPaused
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
        pieces = []
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
        pieces = []
        analysis = nil
        analysisError = nil
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
                // A sentence every 4 s, so transcript search hits have a moment to seek to.
                var sentences: [String] = []
                debugTranscript.enumerateSubstrings(in: debugTranscript.startIndex..., options: .bySentences) { s, _, _, _ in
                    if let s { sentences.append(s) }
                }
                pieces = sentences.enumerated().map { TranscriptPiece(start: Double($0) * 4, end: Double($0 + 1) * 4, text: $1) }
                await analyze()
                return
            }
            if let timed = await transcribeOnDevice(url) {
                pieces = timed
                transcript = TranscriptPiece.joined(timed)
            } else {
                phase = .transcribing(window: 0, total: 0)
                transcript = try await SpeechFileTranscriber().transcribe(fileAt: url) { [weak self] window, total in
                    await self?.setPhase(.transcribing(window: window, total: total))
                }
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

    private static var onDeviceSpeechAvailable: Bool {
        if #available(iOS 26, *) { return OnDeviceTranscriber.isAvailable }
        return false
    }

    /// Apple's newer on-device model (iOS 26): one pass over the whole file, with timings. Nil when it
    /// isn't available or fails, so the older recognizer gets a turn.
    private func transcribeOnDevice(_ url: URL) async -> [TranscriptPiece]? {
        guard #available(iOS 26, *), OnDeviceTranscriber.isAvailable else { return nil }
        phase = .transcribingOnDevice(percent: 0)
        do {
            let pieces = try await OnDeviceTranscriber().transcribe(fileAt: url) { [weak self] fraction in
                await self?.setPhase(.transcribingOnDevice(percent: Int(fraction * 100)))
            }
            return pieces.isEmpty ? nil : pieces
        } catch {
            return nil
        }
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
        guard AppleIntelligence.unavailableReason == nil, #available(iOS 26, *) else {
            analysisError = (AppleIntelligence.unavailableReason ?? "") + " You can still save the transcript."
            phase = .done
            return
        }
        phase = .analyzing
        do {
            analysis = try await OnDeviceMeetingAnalyzer().analyze(transcript: transcript)
        } catch {
            guard !Task.isCancelled else { return }
            analysisError = error.localizedDescription
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

    /// Saves as a new note, or, given `existing`, adds the recording to the end of that note under
    /// a heading, keeping what was written there.
    @discardableResult
    func save(in context: ModelContext, into existing: Note? = nil) -> Note {
        isSaved = true
        let startedAt = recording?.startTime ?? .now
        var blocks = MeetingNoteBuilder.blocks(analysis: analysis, transcript: transcript)
        if let video {
            // The editor shows runs as plain text, so the address itself is the visible link.
            blocks.insert(Block(type: .paragraph, runs: [InlineRun(text: video.watchURL.absoluteString, linkURL: video.watchURL)]), at: 0)
        }
        let note: Note
        if let existing {
            note = existing
            // Ink stays where it was drawn, so the added section starts below it rather than under it.
            let heading = Block(type: .heading(level: 2),
                                runs: [.plain("Recording · \(startedAt.formatted(.dateTime.month().day().hour().minute()))")],
                                minY: Self.inkBottom(of: note))
            note.blockDocument = BlockDocument(blocks: note.blockDocument.blocks + [heading] + blocks)
            if note.summary == nil { note.summary = analysis?.summary }
            note.touch()
        } else {
            let title = video?.title ?? topicTitle(startedAt: startedAt, analysis: analysis, transcript: transcript)
            note = Note(title: title, summary: analysis?.summary)
            note.blockDocument = BlockDocument(blocks: blocks)
            context.insert(note)
        }

        if let recording {
            // Saved from the failure screen, the transcript is missing or partial.
            let transcribed: Bool = if case .failed = phase { false } else { true }
            // File name only: the app container path changes between installs.
            let saved = Recording(id: recordingID, name: note.title, filePath: recording.url.lastPathComponent,
                                  duration: recording.duration, createdAt: startedAt, isTranscribed: transcribed)
            saved.clockSpans = clockSpans
            // The audio goes in the database too, so it syncs to the note's other devices.
            saved.audioData = try? Data(contentsOf: recording.url, options: .mappedIfSafe)
            if let artifact = note.meetingArtifact {
                Self.append(saved, pieces: pieces, transcript: transcript, summary: analysis?.summary,
                            to: artifact, after: note.recordings ?? [])
            }
            note.recordings = (note.recordings ?? []) + [saved]
            if note.meetingArtifact == nil {
                let artifact = MeetingArtifact(recordingId: saved.id,
                                               status: (transcribed ? MeetingProcessingStatus.ready : .failed).rawValue,
                                               summary: analysis?.summary, fullTranscript: transcript)
                artifact.recording = saved
                artifact.segments = pieces.map {
                    TranscriptSegment(artifactId: artifact.id, startTime: $0.start, endTime: $0.end, text: $0.text)
                }
                note.meetingArtifact = artifact
            }
        } else if video != nil {
            // No audio to point at: the artifact carries the timed captions, so the note can be
            // asked about and its transcript searched like a recorded meeting.
            let artifact = MeetingArtifact(recordingId: UUID(), status: MeetingProcessingStatus.ready.rawValue,
                                           summary: analysis?.summary, fullTranscript: transcript)
            artifact.segments = pieces.map {
                TranscriptSegment(artifactId: artifact.id, startTime: $0.start, endTime: $0.end, text: $0.text)
            }
            note.meetingArtifact = artifact
        }
        return note
    }

    /// The bottom of the note's ink, or nil when it has none.
    private static func inkBottom(of note: Note) -> Double? {
        guard let data = note.drawingData, let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
        return drawing.bounds.maxY
    }

    /// A later recording in a note carries on the note's meeting transcript, after every word and
    /// every recording already in it, so chat and transcript search cover it too.
    static func append(_ recording: Recording, pieces: [TranscriptPiece], transcript: String, summary: String?,
                       to artifact: MeetingArtifact, after earlier: [Recording]) {
        let offset = max((artifact.segments ?? []).map(\.endTime).max() ?? 0,
                         earlier.map { $0.transcriptOffset + $0.duration }.max() ?? 0)
        recording.transcriptOffset = offset
        artifact.segments = (artifact.segments ?? []) + pieces.map {
            TranscriptSegment(artifactId: artifact.id, startTime: offset + $0.start, endTime: offset + $0.end, text: $0.text)
        }
        artifact.fullTranscript = joined(artifact.fullTranscript, transcript)
        artifact.summary = joined(artifact.summary, summary)
    }

    /// Two passages as one, either of which may be missing.
    private static func joined(_ first: String?, _ second: String?) -> String? {
        let parts = [first, second].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}
