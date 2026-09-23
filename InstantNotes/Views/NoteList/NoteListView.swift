//
//  NoteListView.swift
//  Instant Notes
//
// Main note list with search over title/plainText/tags. Entry point of the app.

import SwiftUI
import SwiftData

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
    @State private var showSettings = false
    @State private var showMeetingCapture = false
    @State private var showImport = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                searchField
                noteList
            }
            .navigationTitle("Instant Notes")
            .toolbar { toolbarContent }
            // Not on the toolbar button: importing re-renders the list, which would reset the sheet mid-import.
            .sheet(isPresented: $showImport) { ImportView() }
        } detail: {
            if let note = allNotes.first(where: { $0.id == selectedNoteID }) {
                CanvasNoteEditorView(note: .constant(note))
                    .id(note.id)
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

    @ViewBuilder
    private var noteList: some View {
        let filtered = filteredNotes

        if filtered.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "Your notebook is empty" : "No matches",
                systemImage: searchText.isEmpty ? "mic.fill" : "magnifyingglass",
                description: Text(searchText.isEmpty ? "Tap the mic to capture a meeting, or + for a blank page." : "Try a different search term.")
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
                }
                .contextMenu {
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
        if selectedNoteID == note.id { selectedNoteID = nil }
        modelContext.delete(note)
    }

    private var filteredNotes: [Note] {
        var notes = allNotes

        // Filter by search
        if !searchText.isEmpty {
            notes = notes.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.summary ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.tags).joined().localizedCaseInsensitiveContains(searchText) ||
                $0.blockDocument.plainText.localizedCaseInsensitiveContains(searchText)
            }
        }

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
                    showSettings = true
                } label: {
                    Label("AI", systemImage: "sparkles")
                }
                Button {
                    showImport = true
                } label: {
                    Label("Import from Notion", systemImage: "square.and.arrow.down")
                }
                if selectedNoteID != nil {
                    Divider()
                    Button(role: .destructive) {
                        if let note = allNotes.first(where: { $0.id == selectedNoteID }) {
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
            .sheet(isPresented: $showSettings) {
                NavigationStack { AISettingsView() }
            }
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
            Button { showMeetingCapture = true } label: {
                Image(systemName: "mic.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Record meeting")
            .sheet(isPresented: $showMeetingCapture, onDismiss: openCreatedNote) {
                NavigationStack {
                    MeetingCaptureView { createdNoteID = $0.id }
                }
            }
        }
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

    /// The AI summary when there is one, else the note's own text, so typed notes aren't title-only rows.
    private var preview: String {
        if let summary = note.summary, !summary.isEmpty { return summary }
        return note.blockDocument.plainText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

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

            if !preview.isEmpty {
                Text(preview.prefix(120))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .listRowSeparatorTint(Color("RuleColor"))
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
    let idx = abs(tag.hashValue) % palette.count
    return palette[idx]
}
