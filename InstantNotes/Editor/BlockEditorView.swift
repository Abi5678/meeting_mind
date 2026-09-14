//
//  BlockEditorView.swift
//  Instant Notes
//
// Main editor view combining blocks + ink canvas with paper design identity.

import SwiftUI
import MeetingMindKit

struct CanvasNoteEditorView: View {
    @Binding var note: Note
    @StateObject private var state = CanvasEditorState()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Layer 1: paper background with ruled lines and margin accent
            PaperCanvasBackground()

            // Layer 2: block editor scroll view
            ScrollView {
                LazyVStack(spacing: 0) {
                    if state.document.isEmpty {
                        Spacer(minLength: 60)
                    }
                    ForEach(state.document.blocks.map({ ($0, state.document.order.firstIndex(of: $0.id)!)})) { block, index in
                        BlockRowView(block: block, isFocused: .constant(false))
                            .onTapGesture(count: 2) { /* double-tap to focus and edit */ }
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            // Floating add block button (top-right of canvas)
            AddBlockPicker(onInsert: state.insertBlock)
                .padding(.trailing, 16)
        }
        .onAppear {
            state.load(from: note)
        }
        .onChange(of: note) { _, _ in
            state.load(from: note)
        }
    }
}

// MARK: - CanvasEditorState

@MainActor
final class CanvasEditorState: ObservableObject {
    @Published var document = BlockDocument()
    @Published var listCounters: [String: Int] = [:]
    @Published var pendingUpdateTimer: Timer?

    func load(from note: Note) {
        document = note.blockDocument
        updateListCounters()
    }

    func save(to note: Note) {
        // Debounced persistence — in production this would be a timer-based debounce
        note.blocksJSON = (try? JSONEncoder().encode(SwiftDataBlockDocument(document: document)).data(using: .utf8)) ?? "[]"
        note.touch()
    }

    func insertBlock(_ type: Block.BlockType) {
        let newBlock = Block(type: type, runs: [.plain(type.defaultPlaceholder)])
        let index = document.insert(newBlock, after: nil)
        listCounters[newBlock.id.uuidString] = 1
        // If inserted as bulleted/numbered list, also counter the previous sibling
        if index > 0, let prevID = document.order[safe: index - 1], let prev = document.blocksByID[prevID] {
            if case (.bulletedList, .numberedList) = (prev.type, type) {
                listCounters[newBlock.id.uuidString] = listCounters[prevID.uuidString, default: 0] + 1
            } else if case (.numberedList, .numberedList) = (prev.type, type) {
                let prevCounter = listCounters[prevID.uuidString, default: 1]
                listCounters[newBlock.id.uuidString] = prevCounter + 1
            }
        }
    }

    func updateBlock(_ id: UUID, transform: (inout Block) -> Void) {
        document.update(id, transform: transform)
    }

    // MARK: - Helpers

    private func updateListCounters() {
        listCounters.removeAll()
        var counter = 0
        for blockID in document.order {
            if let block = document.blocksByID[blockID] {
                switch block.type {
                case .bulletedList, .numberedList:
                    counter += 1
                    listCounters[blockID.uuidString] = counter
                default:
                    // Reset counter for other block types
                    counter = 0
                }
            }
        }
    }
}

// MARK: - Paper Canvas Background

struct PaperCanvasBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Warm cream paper background
                Color(red: 0.976, green: 0.945, blue: 0.937)

                // Ruled lines (horizontal at 32pt intervals)
                RuledLinesOverlay(height: geo.size.height)

                // Red margin accent line at 72pt from left (legal pad convention)
                VerticalMarginLine(x: 72)
            }
        }
    }
}

struct RuledLinesOverlay: View {
    let height: CGFloat
    private let spacing: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            Path { path in
                for y in stride(from: spacing, through: geo.size.height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color(red: 0.72, green: 0.84, blue: 0.96).opacity(0.15), lineWidth: 0.5)
        }
    }
}

struct VerticalMarginLine: View {
    let x: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color(red: 0.85, green: 0.25, blue: 0.25).opacity(0.3))
            .frame(width: 1)
            .position(x: x + 0.5, y: .infinity / 2) // center vertically
    }
}

// MARK: - Add Block Picker

struct AddBlockPicker: View {
    @State private var isPresented = false
    let onInsert: (Block.BlockType) -> Void

    var body: some View {
        Menu {
            ForEach(blockTypes, id: \.rawValue) { type in
                Button {
                    onInsert(type)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: type.iconName)
                            .font(.caption)
                            .frame(width: 24)
                        Text(type.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.title3)
                .foregroundStyle(Color("InkColor"))
                .padding(8)
                .background(Circle().fill(Color.paperBackgroundLight))
        }
    }

    private var blockTypes: [Block.BlockType] {
        [
            .paragraph,
            .heading(level: 1), .heading(level: 2), .heading(level: 3),
            .bulletedList, .numberedList, .todo, .toggle,
            .quote, .callout(emoji: "💡"), .code(nil), .divider
        ]
    }
}

// MARK: - Block Markdown Shortcut Detection

enum BlockMarkdownShortcut {
    case paragraph
    case heading1, heading2, heading3
    case bulletedList, numberedList
    case todo, toggle, quote, code

    /// Match a markdown prefix against known shortcuts.
    static func fromPrefix(_ input: String) -> Self? {
        let trimmed = input.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
        if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") { return .heading1 }
        if trimmed.hasPrefix("## ") { return .heading2 }
        if trimmed.hasPrefix("### ") { return .heading3 }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") { return .bulletedList }
        if let range = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            return .numberedList
        }
        if trimmed.hasPrefix("[ ] ") || trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[-] ") { return .todo }
        if trimmed.hasPrefix("> ") { return .quote }
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { return .code }
        if trimmed.hasPrefix("- [ ] ") { return .toggle } // some Notion toggle conventions
        return nil
    }

    var blockType: Block.BlockType {
        switch self {
        case .paragraph: .paragraph
        case .heading1: .heading(level: 1)
        case .heading2: .heading(level: 2)
        case .heading3: .heading(level: 3)
        case .bulletedList: .bulletedList
        case .numberedList: .numberedList
        case .todo: .todo
        case .toggle: .toggle
        case .quote: .quote
        case .code: .code(language: nil)
        }
    }

    var prefixLength: Int {
        switch self {
        case .paragraph, .heading1, .bulletedList, .todo, .toggle, .quote, .code: 2
        case .heading2: 3
        case .heading3: 4
        case .numberedList: -1 // variable length — handled by caller
        }
    }
}

// MARK: - Helper extension for safe array access

extension Array {
    subscript(safe index: Index) -> Element? {
        guard index >= startIndex, index < endIndex else { return nil }
        return self[index]
    }
}
