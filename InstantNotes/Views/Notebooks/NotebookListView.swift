//
//  NotebookListView.swift
//  Instant Notes
//
// The notebooks, in the sidebar in place of the notes when "Notebooks" is picked.

import SwiftUI
import SwiftData

struct NotebookListView: View {
    @Binding var selection: UUID?

    @Query(sort: \Notebook.modifiedAt, order: .reverse) private var notebooks: [Notebook]
    @Environment(\.modelContext) private var modelContext
    @State private var renaming: Notebook?
    @State private var renameText = ""
    @State private var showRename = false

    var body: some View {
        Group {
            if notebooks.isEmpty {
                ContentUnavailableView(
                    "No notebooks yet",
                    systemImage: "books.vertical",
                    description: Text("Tap + to gather PDFs, web pages and notes on one topic, then summarize them together and ask questions.")
                )
            } else {
                List(notebooks, selection: $selection) { notebook in
                    NavigationLink(value: notebook.id) {
                        NotebookRow(notebook: notebook)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { delete(notebook) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { beginRename(notebook) } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                    }
                    .contextMenu {
                        Button { beginRename(notebook) } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) { delete(notebook) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .alert("Rename notebook", isPresented: $showRename, presenting: renaming) { notebook in
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename(notebook) }
        }
    }

    /// Its sources and summary stay in your notes; only the notebook and its chat go.
    private func delete(_ notebook: Notebook) {
        if selection == notebook.id { selection = nil }
        modelContext.delete(notebook)
    }

    private func beginRename(_ notebook: Notebook) {
        renaming = notebook
        renameText = notebook.title
        showRename = true
    }

    private func rename(_ notebook: Notebook) {
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != notebook.title else { return }
        notebook.title = title
        notebook.modifiedAt = .now
    }
}

private struct NotebookRow: View {
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(notebook.title)
                .font(.headline)
                .foregroundStyle(Color("InkColor"))
                .lineLimit(1)
            let count = notebook.sources?.count ?? 0
            Text("\(count == 1 ? "1 source" : "\(count) sources") · \(notebook.modifiedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .listRowSeparatorTint(Color("RuleColor"))
    }
}
