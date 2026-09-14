//
//  ImportView.swift
//  Instant Notes
//
// UI for selecting and importing a Notion export ZIP.

import SwiftUI

struct ImportView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel = ImportViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                // Paper background
                Color(red: 0.976, green: 0.945, blue: 0.937).ignoresSafeArea()

                VStack(spacing: 32) {
                    if viewModel.state == .idle {
                        ImportEmptyStateView(onImport: { viewModel.startImport() })
                    } else if viewModel.isProcessing {
                        ImportProgressView(progress: viewModel.progress, status: viewModel.statusMessage)
                    } else if let result = viewModel.result {
                        ImportResultView(result: result, onDone: { presentationMode.wrappedValue.dismiss() })
                    }
                }
            }
            .navigationTitle("Import Notion")
            .toolbar { doneToolbar }
        }
    }

    private var doneToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if viewModel.state == .complete || viewModel.isProcessing {
                Button("Done") { presentationMode.wrappedValue.dismiss() }
                    .disabled(!viewModel.isProcessed)
            } else {
                Button("Cancel") { presentationMode.wrappedValue.dismiss() }
            }
        }
    }
}

// MARK: - Import ViewModel

@MainActor
final class ImportViewModel: ObservableObject {
    enum State { case idle, processing, complete }

    @Published var state: State = .idle
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""
    @Published var result: NotionImportCoordinator.ImportResult?
    @Published var isProcessed = false

    private let coordinator = NotionImportCoordinator.shared

    func startImport() {
        state = .processing
        Task { await processFilePicker() }
    }

    private func processFilePicker() async {
        statusMessage = "Selecting file…"

        // Trigger file picker — in production use FileImporter
        guard let selectedURL = pickFile() else { return }

        do {
            statusMessage = "Importing…"
            let result = try await coordinator.importFromZIP(at: selectedURL) { p in
                Task { @MainActor in progress = p }
            }
            await MainActor.run {
                self.result = result
                state = .complete
                isProcessed = true
            }
        } catch {
            await MainActor.run {
                statusMessage = "Import failed: \(error.localizedDescription)"
                state = .idle
            }
        }
    }

    private func pickFile() -> URL? {
        // Stub: in production use FileImporter / UIDocumentPickerViewController
        return nil
    }
}

// MARK: - Import UI Components

struct ImportEmptyStateView: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("Import from Notion")
                .font(.title.bold())

            Text("Select a Notion export ZIP file to import your pages and databases as notes. Supported: Markdown pages, CSV databases.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Button(action: onImport) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Choose File")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct ImportProgressView: View {
    let progress: Double
    let status: String

    var body: some View {
        VStack(spacing: 24) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)

            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if progress > 0 && progress < 1 {
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ImportResultView: View {
    let result: NotionImportCoordinator.ImportResult
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Import Complete")
                .font(.title.bold())

            Text(result.summary)
                .font(.body)
                .multilineTextAlignment(.center)

            if !result.errors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skipped items:")
                        .font(.subheadline.bold())
                    ForEach(result.errors.prefix(5), id: \.self) { err in
                        Text("• \(err)")
                            .font(.caption.monospacedDigit())
                    }
                    if result.errors.count > 5 {
                        Text("+ \(result.errors.count - 5) more skipped items")
                            .font(.caption.italic())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button("Done") { onDone() }
                .buttonStyle(.borderedProminent)
        }
    }
}
