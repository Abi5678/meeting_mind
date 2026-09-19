//
//  ImportView.swift
//  Instant Notes
//
// UI for selecting and importing a Notion export ZIP.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ImportViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                // Paper background
                Color(red: 0.976, green: 0.945, blue: 0.937).ignoresSafeArea()

                VStack(spacing: 32) {
                    if viewModel.state == .idle {
                        ImportEmptyStateView(onImport: { viewModel.startImport() }, message: viewModel.statusMessage)
                    } else if viewModel.isProcessing {
                        ImportProgressView(status: viewModel.statusMessage)
                    } else if let result = viewModel.result {
                        ImportResultView(result: result, onDone: { presentationMode.wrappedValue.dismiss() })
                    }
                }
            }
            .navigationTitle("Import Notion")
            .toolbar { doneToolbar }
            .fileImporter(isPresented: $viewModel.isPickingFile, allowedContentTypes: [.zip]) { selection in
                viewModel.importFile(selection, into: modelContext)
            }
        }
    }

    @ToolbarContentBuilder
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
    @Published var statusMessage: String = ""
    @Published var result: NotionImportCoordinator.ImportResult?
    @Published var isProcessed = false
    @Published var isPickingFile = false

    var isProcessing: Bool { state == .processing }

    func startImport() {
        statusMessage = ""
        isPickingFile = true
    }

    /// Imports the picked ZIP and inserts one note per page.
    func importFile(_ selection: Result<URL, Error>, into context: ModelContext) {
        let url: URL
        switch selection {
        case let .success(picked): url = picked
        case let .failure(error):
            statusMessage = "Couldn't open the file: \(error.localizedDescription)"
            return
        }

        state = .processing
        statusMessage = "Importing…"
        Task {
            // Files outside the app sandbox are readable only inside this scope.
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

            do {
                let result = try await Task.detached { try NotionImportCoordinator.shared.importFromZIP(at: url) }.value
                for page in result.pages {
                    let note = Note(title: page.title)
                    note.blockDocument = page.document
                    context.insert(note)
                }
                self.result = result
                state = .complete
                isProcessed = true
            } catch {
                statusMessage = "Import failed: \(error.localizedDescription)"
                state = .idle
            }
        }
    }
}

// MARK: - Import UI Components

struct ImportEmptyStateView: View {
    let onImport: () -> Void
    var message = ""

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("Import from Notion")
                .font(.title.bold())

            Text("Select a Notion export ZIP (Markdown & CSV format) to import each page as a note. Database tables are skipped for now.")
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

            if !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

struct ImportProgressView: View {
    let status: String

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)

            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
