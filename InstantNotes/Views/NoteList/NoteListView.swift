//
//  NoteListView.swift
//  Instant Notes
//
// Main note list, and search across notes, meeting transcripts and photos. Entry point of the app.

import SwiftUI
import SwiftData
import PhotosUI
import MeetingMindKit

struct NoteListView: View {
    @Query(sort: \Note.modifiedAt, order: .reverse) private var allNotes: [Note]
    @State private var searchText = ""
    @Environment(\.modelContext) private var modelContext
    @State private var showNewNoteSheet = false
    @State private var selectedSort: SortOption = .modified
    @State private var selectedNoteID: UUID?
    /// A note made in a sheet. Opened once the sheet has gone: on iPhone the collapsed split
    /// view ignores a selection that changes while a sheet is still dismissing.
    @State private var createdNoteID: UUID?
    @State private var showMeetingCapture = false
    @State private var captureSource = CaptureSource.microphone
    @State private var showMediaImporter = false
    @State private var showVideoPicker = false
    @State private var pickedVideo: PhotosPickerItem?
    @State private var showYouTubeLink = false
    @State private var youTubeLink = ""
    @State private var showImport = false
    @State private var renamingNote: Note?
    @State private var renameText = ""
    @State private var showRename = false
    @State private var searchEngine = NoteSearchEngine()
    /// `Note.searchSignature` of every note when the index was last built.
    @State private var indexedSignature: Int?
    @State private var results: [SearchResult] = []
    /// The query `results` answer, so "No matches" isn't shown while a search is still running.
    @State private var searchedQuery = ""
    @State private var showAsk = false
    /// A source picked in "Ask your notes", opened once its sheet has gone.
    @State private var askedResultID: SearchResult.ID?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                searchField
                noteList
            }
            .navigationTitle("Recapped")
            .toolbar { toolbarContent }
            // Not on the toolbar button: importing re-renders the list, which would reset the sheet mid-import.
            .sheet(isPresented: $showImport) { ImportView() }
            .alert("Rename note", isPresented: $showRename, presenting: renamingNote) { note in
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { rename(note) }
            }
            .task(id: searchText) { await runSearch() }
            // Photos added before search could read them.
            .task { await PhotoTextRecognition.recognizePending(in: modelContext) }
        } detail: {
            if let note = allNotes.first(where: { $0.id == openNoteID }) {
                // Keyed by the selection, so a second hit in the same note jumps again.
                CanvasNoteEditorView(note: .constant(note), jump: selectedResult?.hit.passage.source)
                    .id(selectedNoteID)
            } else {
                EmptyDetailPlaceholder()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(Color("InkColor").opacity(0.45))
            TextField("Search notes…", text: $searchText)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color("InkColor").opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color("PaperBackground"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color("RuleColor"), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// A selected search result. The list selection is either a note's id or a result's id.
    private var selectedResult: SearchResult? {
        results.first { $0.id == selectedNoteID }
    }

    /// The note in the detail pane, whether picked from the list or from search.
    private var openNoteID: UUID? {
        selectedResult?.hit.passage.noteID ?? selectedNoteID
    }

    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            // Keep the open note open when search is cleared.
            if let result = selectedResult { selectedNoteID = result.hit.passage.noteID }
            results = []
            searchedQuery = ""
            return
        }
        // Let a burst of typing settle before searching.
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }

        let signature = allNotes.map(\.searchSignature).hashValue
        if signature != indexedSignature {
            await searchEngine.rebuild(allNotes.flatMap(\.searchPassages))
            indexedSignature = signature
        }
        let hits = await searchEngine.search(searchText)
        guard !Task.isCancelled else { return }
        results = hits.map(SearchResult.init)
        searchedQuery = searchText
    }

    @ViewBuilder
    private var searchResults: some View {
        if results.isEmpty {
            if searchedQuery == searchText {
                ContentUnavailableView.search(text: searchText.trimmingCharacters(in: .whitespaces))
            } else {
                Spacer()
            }
        } else {
            let titles = Dictionary(allNotes.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
            List(selection: $selectedNoteID) {
                if canAsk {
                    Button { showAsk = true } label: { askRow }
                }
                ForEach(results) { result in
                    NavigationLink(value: result.id) {
                        SearchHitRow(hit: result.hit, noteTitle: titles[result.hit.passage.noteID] ?? "Untitled")
                    }
                }
            }
            .listStyle(.plain)
            .sheet(isPresented: $showAsk, onDismiss: openAskedResult) {
                AskNotesView(question: searchText.trimmingCharacters(in: .whitespaces), results: results,
                             titles: titles) { askedResultID = $0 }
            }
        }
    }

    /// Asking needs Apple's on-device model; without it the row isn't offered.
    private var canAsk: Bool {
        if #available(iOS 26, *) { OnDeviceNotesAnswerer.isAvailable } else { false }
    }

    private var askRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask your notes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("InkColor"))
                Text("“\(searchText.trimmingCharacters(in: .whitespaces))” · answered on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .listRowSeparatorTint(Color("RuleColor"))
    }

    private func openAskedResult() {
        guard let id = askedResultID else { return }
        askedResultID = nil
        selectedNoteID = id
    }

    @ViewBuilder
    private var noteList: some View {
        let filtered = filteredNotes

        if !searchText.isEmpty {
            searchResults
        } else if filtered.isEmpty {
            ContentUnavailableView(
                "Your notebook is empty",
                systemImage: "mic.fill",
                description: Text("Tap the mic to capture a meeting, or + for a blank page.")
            )
        } else {
            List(filtered, id: \.id, selection: $selectedNoteID) { note in
                NavigationLink(value: note.id) {
                    NoteRowView(note: note)
                }
                // Both affordances live on the row, not inside the link's label, where
                // SwiftUI ignores them. Swipe is the iOS gesture; right-click is the Mac one.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { delete(note) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { beginRename(note) } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                }
                .contextMenu {
                    Button { beginRename(note) } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) { delete(note) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    /// Clears the selection first: deleting the open note would otherwise leave the
    /// detail pane pointing at a deleted model object.
    private func delete(_ note: Note) {
        if openNoteID == note.id { selectedNoteID = nil }
        // The relationships have no cascade rule, so the meeting's rows and audio go explicitly.
        let recordingsDirectory = AudioRecorderService.defaultRecordingsDirectory()
        for recording in note.recordings {
            try? FileManager.default.removeItem(at: recordingsDirectory.appending(path: recording.filePath))
            modelContext.delete(recording)
        }
        if let artifact = note.meetingArtifact {
            artifact.segments.forEach(modelContext.delete)
            artifact.chatMessages.forEach(modelContext.delete)
            modelContext.delete(artifact)
        }
        modelContext.delete(note)
    }

    private func beginRename(_ note: Note) {
        renamingNote = note
        renameText = note.title
        showRename = true
    }

    /// An empty name keeps the old title rather than leaving a blank row.
    private func rename(_ note: Note) {
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != note.title else { return }
        note.title = title
        note.touch()
    }

    private var filteredNotes: [Note] {
        var notes = allNotes

        // Apply sort
        switch selectedSort {
        case .modified: break // already sorted by Query
        case .created: notes.sort { $0.createdAt > $1.createdAt }
        case .title: notes.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }

        return notes
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                Picker("Sort by", selection: $selectedSort) {
                    Text("Last Modified").tag(SortOption.modified)
                    Text("Date Created").tag(SortOption.created)
                    Text("Title A–Z").tag(SortOption.title)
                }
                Button {
                    showImport = true
                } label: {
                    Label("Import from Notion", systemImage: "square.and.arrow.down")
                }
                if selectedNoteID != nil {
                    Divider()
                    Button(role: .destructive) {
                        if let note = allNotes.first(where: { $0.id == openNoteID }) {
                            delete(note)
                        }
                    } label: {
                        Label("Delete note", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showNewNoteSheet = true } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New note")
            .sheet(isPresented: $showNewNoteSheet, onDismiss: openCreatedNote) {
                TemplateGalleryView { createdNoteID = $0.id }
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("Record meeting", systemImage: "mic") { capture(.microphone) }
                Button("Import audio or video…", systemImage: "folder") { showMediaImporter = true }
                Button("Video from Photos…", systemImage: "photo.on.rectangle") { showVideoPicker = true }
                Button("Transcribe YouTube link…", systemImage: "play.rectangle") {
                    youTubeLink = ""
                    showYouTubeLink = true
                }
            } label: {
                Image(systemName: "mic.fill")
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Record or import a meeting")
            .fileImporter(isPresented: $showMediaImporter, allowedContentTypes: [.audio, .movie]) { result in
                if case let .success(url) = result { capture(.file(url)) }
            }
            .photosPicker(isPresented: $showVideoPicker, selection: $pickedVideo, matching: .videos)
            .onChange(of: pickedVideo) { _, item in
                guard let item else { return }
                pickedVideo = nil
                capture(.video(item))
            }
            .alert("Transcribe a YouTube video", isPresented: $showYouTubeLink) {
                TextField("youtube.com/watch?v=…", text: $youTubeLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Cancel", role: .cancel) {}
                Button("Transcribe") { capture(.youTube(youTubeLink)) }
            } message: {
                Text("Paste a link to a video with captions. Recapped summarizes the captions; no video is downloaded.")
            }
            .sheet(isPresented: $showMeetingCapture, onDismiss: openCreatedNote) {
                NavigationStack {
                    MeetingCaptureView(source: captureSource) { createdNoteID = $0.id }
                }
            }
        }
    }

    private func capture(_ source: CaptureSource) {
        captureSource = source
        showMeetingCapture = true
    }

    private func openCreatedNote() {
        guard let id = createdNoteID else { return }
        createdNoteID = nil
        selectedNoteID = id
    }

    enum SortOption: String, CaseIterable {
        case modified = "Last Modified"
        case created = "Date Created"
        case title = "Title A-Z"
    }
}

// MARK: - Note Row View

struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if note.tags.count > 0 {
                    ForEach(note.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .foregroundStyle(Color("InkColor"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(highlighterFill(for: tag), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }

                Spacer()

                if note.meetingArtifact != nil {
                    Image(systemName: "waveform")
                        .font(.caption2)
                        .foregroundStyle(Color("InkColor"))
                }
            }

            Text(note.title)
                .font(.headline)
                .foregroundStyle(Color("InkColor"))
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(note.modifiedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                    .layoutPriority(1)
                if let preview {
                    Text(preview)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 4)
        .listRowSeparatorTint(Color("RuleColor"))
    }

    /// The meeting summary when there is one, otherwise the first line written on the page.
    private var preview: String? {
        if let summary = note.summary, !summary.isEmpty { return summary }
        return note.blockDocument.plainText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}

// MARK: - Empty Detail Placeholder (until Phase 7)

struct EmptyDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Open a page",
            systemImage: "book.closed",
            description: Text("Pick a note from the list, or capture a meeting with the mic.")
        )
    }
}


private func highlighterFill(for tag: String) -> Color {
    let palette: [Color] = [
        Color(red: 1.0, green: 0.96, blue: 0.61).opacity(0.55),   // yellow
        Color(red: 0.96, green: 0.56, blue: 0.69).opacity(0.45),  // pink
        Color(red: 0.65, green: 0.84, blue: 0.65).opacity(0.50),  // mint
    ]
    // Not `hashValue`: it is seeded per process, so tags would change colour on every launch.
    let idx = tag.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff } % palette.count
    return palette[idx]
}
