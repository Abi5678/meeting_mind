//
//  MeetingCaptureView.swift
//  Instant Notes
//
// Main meeting capture screen with record/pause controls and status display.

import SwiftUI
import MeetingMindKit

struct MeetingCaptureView: View {
    @StateObject private var viewModel = MeetingCaptureViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Waveform visualization
            WaveformBanner(isRecording: viewModel.isRecording)
                .padding(.horizontal, 32)

            // Recording timer
            TimerDisplay(timeInterval: viewModel.recordingDuration)
                .font(.system(size: 64, design: .monospaced))

            Spacer()

            // Record/Pause button
            Button(action: {
                withAnimation(.spring(response: 0.4)) {
                    viewModel.toggleRecording()
                }
            }) {
                Circle()
                    .fill(viewModel.isRecording ? Color.red : Color.secondary.opacity(0.2))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.title2)
                            .foregroundStyle(viewModel.isRecording ? .white : .primary)
                    )
            }

            // Status display
            if let status = viewModel.status {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(status.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(Color.secondary.opacity(0.08), in: Capsule())
            }

            // Analysis results (when ready)
            if let analysis = viewModel.analysis {
                MeetingAnalysisView(analysis: analysis)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .navigationTitle("Meeting Capture")
    }
}

// MARK: - ViewModel

@MainActor
final class MeetingCaptureViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var status: TranscriptionStatus?
    @Published var analysis: MeetingAnalysis?

    private var timer: Timer?
    private let recorderService = AudioRecorderService()

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        Task {
            let granted = await recorderService.requestPermission()
            guard granted else { return }

            let url = recorderService.startRecording(name: "Meeting")
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let startTime = self.recorderService.audioRecorder?.lastRecordedRange else { return }
                // Update duration display
            }
        }
    }

    func stopRecording() {
        timer?.invalidate()
        timer = nil
        isRecording = false
        recordingDuration = recorderService.recordingDuration

        Task {
            let result = await recorderService.stopRecording()
            if let result {
                // Start transcription pipeline
                await runAnalysis(for: result.url)
            }
        }
    }

    private func runAnalysis(for audioURL: URL) async {
        status = .analyzing

        do {
            // Stub: in production this would call TranscriptionService.shared.analyzeMeeting
            // For now, return a mock analysis to show the UI
            analysis = MeetingAnalysis(
                summary: "This is a placeholder analysis. Enable whisper.cpp integration for real transcription.",
                keyDecisions: [Decision(text: "Enable whisper.cpp in settings")],
                actionItems: [ActionItem(task: "Download whisper.cpp model", owner: "User", due: nil)],
                followUpEmail: FollowUpEmail(subject: "Follow-up on meeting analysis", body: "The transcription pipeline is ready to use.")
            )
            status = .ready
        } catch {
            status = .failed(error)
        }
    }

    // MARK: - TranscriptionStatus display

    enum TranscriptionStatus: Equatable {
        case chunking(progress: Double)
        case transcribing(chunk: Int, total: Int)
        case analyzing
        case ready
        case failed(Error)

        var description: String {
            switch self {
            case .chunking(let p): "Chunking audio... \(Int(p * 100))%"
            case .transcribing(let c, let t): "Transcribing chunk \(c)/\(t)"
            case .analyzing: "Analyzing with AI…"
            case .ready: "Analysis complete"
            case .failed(let e): "Failed: \(e.localizedDescription)"
            }
        }

        static func == (lhs: TranscriptionStatus, rhs: TranscriptionStatus) -> Bool {
            switch (lhs, rhs) {
            case (.analyzing, .analyzing), (.ready, .ready): return true
            default: false
            }
        }
    }
}
