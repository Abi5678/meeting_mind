//
//  TemplateGalleryView.swift
//  Instant Notes
//
// New-note sheet: pick a paper style or a pre-filled layout from a gallery of page previews.

import SwiftUI
import SwiftData
import MeetingMindKit

struct TemplateGalleryView: View {
    /// Called with the inserted note so the list can open it.
    var onCreate: (Note) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title = ""
    @State private var category: NoteTemplate.Category?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    private var templates: [NoteTemplate] {
        guard let category else { return NoteTemplate.all }
        return NoteTemplate.all.filter { $0.category == category }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Note title (optional)", text: $title)
                        .font(.title3)
                        .submitLabel(.done)
                        .padding(12)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                    categoryChips

                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(templates) { template in
                            Button { create(from: template) } label: {
                                TemplateCard(template: template)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(template.name)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isSelected: category == nil) { category = nil }
                ForEach(NoteTemplate.Category.allCases, id: \.self) { item in
                    chip(item.rawValue, isSelected: category == item) { category = item }
                }
            }
        }
    }

    private func chip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func create(from template: NoteTemplate) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let fallback = template.category == .paper ? "Untitled" : template.name
        let note = Note(title: trimmed.isEmpty ? fallback : trimmed)
        note.paper = template.paper
        note.blockDocument = BlockDocument(blocks: template.makeBlocks())
        modelContext.insert(note)
        dismiss()
        onCreate(note)
    }
}

/// A page-shaped preview of a template: its paper with the first few lines drawn on it.
private struct TemplateCard: View {
    let template: NoteTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                PaperCanvasBackground(style: template.paper)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(previewLines.enumerated()), id: \.offset) { _, line in
                        PreviewLine(block: line.block, number: line.number)
                    }
                }
                .padding(.top, 14)
                .padding(.leading, template.paper == .lined ? 50 : 14)
                .padding(.trailing, 10)
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            .padding(.bottom, 6)

            Text(template.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(template.category.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    /// The first lines of the template, with each run of numbered items counted from 1.
    private var previewLines: [(block: Block, number: Int)] {
        var count = 0
        return template.makeBlocks().prefix(9).map { block in
            count = block.type == .numberedList ? count + 1 : 0
            return (block, count)
        }
    }
}

private struct PreviewLine: View {
    let block: Block
    let number: Int

    var body: some View {
        HStack(spacing: 4) {
            switch block.type {
            case .todo:
                Image(systemName: "square")
            case .bulletedList:
                Text("•")
            case .numberedList:
                Text("\(number).")
            case let .callout(emoji):
                Text(emoji)
            case .quote:
                Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 2, height: 10)
            default:
                EmptyView()
            }

            if block.plainText.isEmpty {
                // A fill-in line, like the blank rule on a printed planner.
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(maxWidth: 70, maxHeight: 3)
            } else {
                Text(block.plainText)
                    .lineLimit(1)
            }
        }
        .font(isHeading ? .system(size: 11, weight: .bold) : .system(size: 9))
        .foregroundStyle(Color("InkColor"))
    }

    private var isHeading: Bool {
        if case .heading = block.type { return true }
        return false
    }
}
