//
//  NotebookView.swift
//  Instant Notes
//
// One notebook: its summary, its sources, and adding more from files, web pages or existing notes.
// Imported documents become ordinary notes, so they can be read, edited and searched like any other.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MeetingMindKit

/// A notebook with its own navigation, so its sources and summary open inside it.
struct NotebookScreen: View {
    let notebook: Notebook
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            NotebookView(notebook: notebook, path: $path)
                .navigationDestination(for: UUID.self) { NoteDestination(id: $0) }
        }
    }
}

private struct NoteDestination: View {
    @Query private var notes: [Note]

    init(id: UUID) {
        _notes = Query(filter: #Predicate<Note> { $0.id == id })
    }

    var body: some View {
        if let note = notes.first {
            CanvasNoteEditorView(note: .constant(note))
        } else {
            ContentUnavailableView("This note was deleted", systemImage: "doc")
        }
    }
}

struct NotebookView: View {
    let notebook: Notebook
    @Binding var path: [UUID]

    @Environment(\.modelContext) private var modelContext
    @Query private var allNotes: [Note]
    @State private var showFileImporter = false
    @State private var showWebLink = false
    @State private var webLink = ""
    @State private var showNotePicker = false
    /// What's being imported right now, in words for the user.
    @State private var importing: String?
    @State private var importError: String?
    @State private var showChat = false
    /// A source cited in the chat, opened once its sheet has gone.
    @State private var citedNoteID: UUID?

    private var summaries: NotebookSummaries { .shared }

    private static let documentTypes: [UTType] = [.pdf, .plainText, .rtf] + [UTType(filenameExtension: "md")].compactMap { $0 }

    private var sources: [Note] { notebook.orderedSources }

    private var summaryNote: Note? {
        notebook.summaryNoteID.flatMap { id in allNotes.first { $0.id == id } }
    }

    var body: some View {
        List {
            Section { summaryCard }
            Section {
                sourceRows
            } header: {
                Text(sources.isEmpty ? "Sources" : "Sources (\(sources.count))")
            }
        }
        .navigationTitle(notebook.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                addMenu { Label("Add source", systemImage: "plus") }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: Self.documentTypes, allowsMultipleSelection: true) { result in
            switch result {
            case let .success(urls): Task { await importFiles(urls) }
            case let .failure(error): importError = error.localizedDescription
            }
        }
        .alert("Add a web page", isPresented: $showWebLink) {
            TextField("example.com/article", text: $webLink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Cancel", role: .cancel) {}
            Button("Add") { Task { await importWebPage(webLink) } }
        } message: {
            Text("Quolio saves the article's text as a note in this notebook.")
        }
        .alert("Couldn't add that", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .sheet(isPresented: $showNotePicker) {
            SourceNotePicker(excluded: Set(sources.map(\.id))) { addSources($0) }
        }
        .sheet(isPresented: $showChat, onDismiss: openCitedNote) {
            NotebookChatView(notebook: notebook) { citedNoteID = $0 }
        }
    }

    // MARK: - Summary

    private var needsSummary: Bool { notebook.summaryIsStale || summaryNote == nil }

    @ViewBuilder
    private var summaryCard: some View {
        let summary = summaryNote
        VStack(alignment: .leading, spacing: 12) {
            if let summary, let overview = summary.summary, !overview.isEmpty {
                Text(overview)
                    .foregroundStyle(Color("InkColor"))
                    .lineLimit(10)
            } else if sources.isEmpty {
                Text("Add PDFs, web pages, text files, or your own notes and recordings. Quolio summarizes them together and answers your questions about them, all on this device.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Summarize to see what your sources cover together: the key themes, and where they agree and differ.")
                    .foregroundStyle(.secondary)
            }

            if !sources.isEmpty {
                HStack(spacing: 10) {
                    if let summary {
                        Button("Open summary", systemImage: "doc.text") { path.append(summary.id) }
                            .buttonStyle(.bordered)
                    }
                    Button("Ask", systemImage: "bubble.left.and.text.bubble.right") { showChat = true }
                        .buttonStyle(.bordered)
                }
            }

            if let progress = summaries.progress[notebook.id] {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(progress)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if !sources.isEmpty {
                if needsSummary {
                    Button(summary == nil ? "Summarize" : "Update summary", systemImage: "sparkles") {
                        Task { await summaries.summarize(notebook, in: modelContext) }
                    }
                    .buttonStyle(.borderedProminent)
                    if summary != nil {
                        Text("Sources have changed since this summary. Updating reads only the new and changed ones.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let summary {
                    // Redrawn each minute, so "written 2 minutes ago" doesn't stay that way.
                    TimelineView(.everyMinute) { _ in
                        Text("Up to date · written \(summary.modifiedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = summaries.errors[notebook.id] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Sources

    @ViewBuilder
    private var sourceRows: some View {
        let read = notebook.currentDigests
        let digested = Set(notebook.digests.map(\.noteID))
        ForEach(sources) { note in
            NavigationLink(value: note.id) {
                SourceRow(note: note, isRead: read[note.id] != nil, wasRead: digested.contains(note.id))
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { remove(note) } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
            }
            .contextMenu {
                Button(role: .destructive) { remove(note) } label: {
                    Label("Remove from notebook", systemImage: "minus.circle")
                }
            }
        }
        if let importing {
            HStack(spacing: 10) {
                ProgressView()
                Text(importing).foregroundStyle(.secondary)
            }
        }
        if sources.isEmpty, importing == nil {
            addMenu {
                Label("Add a source", systemImage: "plus.circle.fill")
            }
        }
    }

    private func addMenu<Content: View>(@ViewBuilder label: () -> Content) -> some View {
        Menu {
            Button("PDF or text file…", systemImage: "doc") { showFileImporter = true }
            Button("Web page…", systemImage: "globe") {
                webLink = ""
                showWebLink = true
            }
            Button("Notes and recordings…", systemImage: "note.text") { showNotePicker = true }
        } label: {
            label()
        }
        .disabled(importing != nil)
    }

    /// Takes it out of this notebook and its summary; the note itself stays.
    private func remove(_ note: Note) {
        notebook.sources?.removeAll { $0.id == note.id }
        notebook.digests.removeAll { $0.noteID == note.id }
        notebook.modifiedAt = .now
    }

    private func addSources(_ notes: [Note]) {
        guard !notes.isEmpty else { return }
        notebook.sources = (notebook.sources ?? []) + notes
        notebook.modifiedAt = .now
    }

    private func add(_ document: ImportedDocument) {
        let note = Note(title: document.title)
        note.blockDocument = document.document
        modelContext.insert(note)
        addSources([note])
    }

    private func importFiles(_ urls: [URL]) async {
        var failures: [String] = []
        for url in urls {
            importing = "Reading “\(url.lastPathComponent)”…"
            let access = url.startAccessingSecurityScopedResource()
            // Reading a long PDF, and the words in its scanned pages, takes a while.
            let result = await Task.detached(priority: .userInitiated) {
                Result { try DocumentReader.read(url) }
            }.value
            if access { url.stopAccessingSecurityScopedResource() }
            switch result {
            case let .success(document): add(document)
            case let .failure(error): failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        importing = nil
        if !failures.isEmpty { importError = failures.joined(separator: "\n\n") }
    }

    private func importWebPage(_ link: String) async {
        guard !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        importing = "Reading the page…"
        defer { importing = nil }
        do {
            add(try await Task.detached(priority: .userInitiated) { try await WebPageReader.read(link) }.value)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func openCitedNote() {
        guard let id = citedNoteID else { return }
        citedNoteID = nil
        path.append(id)
    }
}

private struct SourceRow: View {
    let note: Note
    /// Whether the summary has read this source as it is now.
    let isRead: Bool
    /// Read for the summary, but changed since.
    let wasRead: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: note.meetingArtifact != nil ? "waveform" : "doc.text")
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.headline)
                    .foregroundStyle(Color("InkColor"))
                    .lineLimit(2)
                TimelineView(.everyMinute) { _ in
                    Text(isRead ? "Updated \(note.modifiedAt.formatted(.relative(presentation: .named)))"
                         : wasRead ? "Changed since the summary" : "Not in the summary yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Picks existing notes and recordings to add as sources.
private struct SourceNotePicker: View {
    /// Notes already in the notebook.
    let excluded: Set<UUID>
    let onAdd: ([Note]) -> Void

    @Query(sort: \Note.modifiedAt, order: .reverse) private var notes: [Note]
    @Query private var notebooks: [Notebook]
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [UUID] = []
    @State private var search = ""

    /// Everything but this notebook's sources and the notebooks' own summaries.
    private var shown: [Note] {
        let summaries = Set(notebooks.compactMap(\.summaryNoteID))
        let query = search.trimmingCharacters(in: .whitespaces)
        return notes.filter { note in
            !excluded.contains(note.id) && !summaries.contains(note.id)
                && (query.isEmpty || note.title.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            List(shown) { note in
                Button { toggle(note.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: picked.contains(note.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(picked.contains(note.id) ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                                .foregroundStyle(Color("InkColor"))
                                .lineLimit(2)
                            Text(note.modifiedAt.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if note.meetingArtifact != nil {
                            Image(systemName: "waveform").foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .overlay {
                if shown.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No other notes" : "No matches", systemImage: "note.text")
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Add notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(picked.isEmpty ? "Add" : "Add (\(picked.count))") {
                        onAdd(picked.compactMap { id in notes.first { $0.id == id } })
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if let index = picked.firstIndex(of: id) { picked.remove(at: index) } else { picked.append(id) }
    }
}
