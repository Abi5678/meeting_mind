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

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                searchField
                Divider()
                    .padding(.horizontal, 16)
                noteList
            }
            .navigationTitle("Notes")
            .toolbar { toolbarContent }
        } detail: {
            // Detail pane — filled by Phase 7 when a note is selected
            EmptyDetailPlaceholder()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("Search notes…", text: $searchText)
                .font(.body)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var noteList: some View {
        let filtered = filteredNotes

        if filtered.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No notes yet" : "No matches",
                systemImage: searchText.isEmpty ? "note.text" : "magnifyingglass",
                description: Text(searchText.isEmpty ? "Tap + to create your first note." : "Try a different search term.")
            )
        } else {
            List(filtered, id: \.id) { note in
                NavigationLink {
                    NoteEditorView(note: .constant(note))
                } label: {
                    NoteRowView(note: note)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                modelContext.delete(note)
                            } label: {
                                Image(systemName: "trash")
                                Text("Delete")
                            }
                        }
                }
            }
            .listStyle(.plain)
        }
    }

    private var filteredNotes: [Note] {
        var notes = allNotes

        // Filter by search
        if !searchText.isEmpty {
            notes = notes.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.summary ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.tags).joined().localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply sort
        switch selectedSort {
        case .modified: break // already sorted by Query
        case .created: notes.sort { $0.createdAt > $1.createdAt }
        case .title: notes.sort { $0.title < $1.title }
        }

        return notes
    }

    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                Picker("Sort by", selection: $selectedSort) {
                    Text("Last Modified").tag(SortOption.modified)
                    Text("Date Created").tag(SortOption.created)
                    Text("Title A-Z").tag(SortOption.title)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption2)
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showNewNoteSheet = true } label: {
                Image(systemName: "plus")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showNewNoteSheet) {
                NewNoteSheet()
            }
        }
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
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                }

                Spacer()

                if note.meetingArtifact != nil {
                    Image(systemName: "waveform")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Text(note.title)
                .font(.headline)
                .lineLimit(1)

            if let summary = note.summary, !summary.isEmpty {
                Text(summary.prefix(80))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty Detail Placeholder (until Phase 7)

struct EmptyDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Select a note",
            systemImage: "note.text",
            description: Text("Choose a note from the list to start editing.")
        )
    }
}

// MARK: - New Note Sheet

struct NewNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Note title", text: $title)
                    .textContentType(.name)
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let note = Note(title: title.isEmpty ? "Untitled" : title)
                        modelContext.insert(note)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}
