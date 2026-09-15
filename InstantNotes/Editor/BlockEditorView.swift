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
    @FocusState private var focusedBlockID: UUID?
    @State private var showQuiz = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Layer 1: paper background in the note's chosen style
            PaperCanvasBackground(style: note.paper)
                .ignoresSafeArea(edges: .bottom)

            // Layer 2: block editor scroll view
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.document.blocks) { block in
                        BlockRowView(block: block, focusedBlockID: $focusedBlockID)
                    }
                    // Tapping below the last block continues writing there.
                    Color.clear
                        .frame(height: 240)
                        .contentShape(Rectangle())
                        .onTapGesture { focusOrAddTrailingBlock() }
                }
                // Clears the floating + button and sits content right of the margin line.
                .padding(.top, 56)
                .padding(.leading, 20)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Floating add block button (top-right of canvas)
            AddBlockPicker(onInsert: { focus(state.insertBlock($0, after: focusedBlockID)) })
                .padding(.trailing, 16)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Paper", selection: Binding(get: { note.paper }, set: { note.paper = $0 })) {
                        ForEach(PaperStyle.allCases, id: \.self) { style in
                            Text(style.rawValue.capitalized).tag(style)
                        }
                    }
                } label: {
                    Image(systemName: "doc.plaintext")
                }
                .accessibilityLabel("Paper style")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showQuiz = true } label: {
                    Label("Quiz me", systemImage: "brain.head.profile")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.bold())
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.pink)
            }
            ToolbarItemGroup(placement: .keyboard) {
                if let id = focusedBlockID {
                    Menu {
                        ForEach(AddBlockPicker.blockTypes, id: \.displayName) { type in
                            Button { state.updateBlock(id) { $0.type = type } } label: {
                                Label(type.displayName, systemImage: type.iconName)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) { focus(state.removeBlock(id)) } label: {
                        Image(systemName: "trash")
                    }
                }
                Spacer()
                Button("Done") { focusedBlockID = nil }
            }
        }
        .fullScreenCover(isPresented: $showQuiz) {
            QuizView(noteTitle: note.title, notesText: state.document.plainText)
        }
        .environmentObject(state)
        .onAppear {
            state.load(from: note)
            // A brand-new note opens ready to type.
            if state.document.isEmpty {
                let id = state.insertBlock(.paragraph, after: nil)
                // Focus set while the push animation runs is dropped, so wait for it to finish.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { focusedBlockID = id }
            }
        }
        .onChange(of: note) { _, _ in
            state.load(from: note)
        }
        .onChange(of: state.document) { _, document in
            if document != note.blockDocument { state.save(to: note) }
        }
    }

    /// Focus is applied on the next run loop so a just-inserted row exists to receive it.
    private func focus(_ id: UUID?) {
        guard let id else { return }
        DispatchQueue.main.async { focusedBlockID = id }
    }

    private func focusOrAddTrailingBlock() {
        if let last = state.document.blocks.last, last.plainText.isEmpty, last.type != .divider {
            focus(last.id)
        } else {
            focus(state.insertBlock(.paragraph, after: nil))
        }
    }
}

// MARK: - CanvasEditorState

@MainActor
final class CanvasEditorState: ObservableObject {
    @Published var document = BlockDocument() {
        didSet { updateListCounters() }
    }
    @Published var listCounters: [String: Int] = [:]
    @Published var pendingUpdateTimer: Timer?

    func load(from note: Note) {
        document = note.blockDocument
        updateListCounters()
    }

    func save(to note: Note) {
        // Debounced persistence — in production this would be a timer-based debounce
        note.blockDocument = document
        note.touch()
    }

    /// Inserts after `id` (the focused block), or at the end of the note when nothing is focused.
    @discardableResult
    func insertBlock(_ type: BlockType, after id: UUID?) -> UUID {
        let newBlock = Block(type: type)
        if let id, document.blocksByID[id] != nil {
            _ = document.insert(newBlock, after: id)
        } else {
            document.append(newBlock)
        }
        return newBlock.id
    }

    func updateBlock(_ id: UUID, transform: (inout Block) -> Void) {
        document.update(id, transform: transform)
    }

    /// Replaces a block's text with the first line and inserts one block per remaining line.
    /// Returns the block that should take focus.
    func splitBlock(_ id: UUID, into lines: [String]) -> UUID? {
        guard let block = document.blocksByID[id], let first = lines.first else { return nil }
        let continuesList = [BlockType.bulletedList, .numberedList, .todo].contains(block.type)

        // Return on an empty list item leaves the list, as in Notion.
        if lines == ["", ""], block.plainText.isEmpty, continuesList {
            document.update(id) { $0.type = .paragraph }
            return id
        }

        document.update(id) { $0.runs = first.isEmpty ? [] : [.plain(first)] }
        var previousID = id
        for line in lines.dropFirst() {
            let next = Block(
                type: continuesList ? block.type : .paragraph,
                runs: line.isEmpty ? [] : [.plain(line)],
                indent: block.indent
            )
            _ = document.insert(next, after: previousID)
            previousID = next.id
        }
        return previousID
    }

    /// Removes a block and returns the block before it, for focus.
    func removeBlock(_ id: UUID) -> UUID? {
        let index = document.order.firstIndex(of: id)
        _ = document.remove(id)
        guard let index, index > 0 else { return document.order.first }
        return document.order[safe: index - 1]
    }

    // MARK: - Helpers

    /// Numbers each run of consecutive numbered-list blocks from 1.
    private func updateListCounters() {
        var counters: [String: Int] = [:]
        var counter = 0
        for block in document.blocks {
            if block.type == .numberedList {
                counter += 1
                counters[block.id.uuidString] = counter
            } else {
                counter = 0
            }
        }
        if counters != listCounters { listCounters = counters }
    }
}

// MARK: - Paper Canvas Background

struct PaperCanvasBackground: View {
    var style: PaperStyle = .lined

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Warm cream paper background (warm charcoal in dark mode)
                Color("PaperBackground")

                switch style {
                case .lined:
                    // Ruled lines (horizontal at 32pt intervals)
                    RuledLinesOverlay(height: geo.size.height)

                    // Red margin accent line, left of the block chrome (legal pad convention)
                    VerticalMarginLine(x: 40)
                case .grid:
                    GridLinesOverlay()
                case .dotted:
                    DotGridOverlay()
                case .blank:
                    EmptyView()
                }
            }
        }
    }
}

struct GridLinesOverlay: View {
    private let spacing: CGFloat = 24

    var body: some View {
        Canvas { context, size in
            var path = Path()
            for x in stride(from: spacing, through: size.width, by: spacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: spacing, through: size.height, by: spacing) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(Color(red: 0.72, green: 0.84, blue: 0.96).opacity(0.45)), lineWidth: 0.5)
        }
    }
}

struct DotGridOverlay: View {
    private let spacing: CGFloat = 20

    var body: some View {
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: spacing, through: size.width, by: spacing) {
                for y in stride(from: spacing, through: size.height, by: spacing) {
                    dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                }
            }
            context.fill(dots, with: .color(Color.gray.opacity(0.4)))
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, x)
    }
}

// MARK: - Add Block Picker

struct AddBlockPicker: View {
    @State private var isPresented = false
    let onInsert: (BlockType) -> Void

    var body: some View {
        Menu {
            ForEach(Self.blockTypes, id: \.displayName) { type in
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
                .background(Circle().fill(Color("PaperBackground")))
        }
    }

    static var blockTypes: [BlockType] {
        [
            .paragraph,
            .heading(level: 1), .heading(level: 2), .heading(level: 3),
            .bulletedList, .numberedList, .todo, .toggle,
            .quote, .callout(emoji: "💡"), .code(language: nil), .divider
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

    var blockType: BlockType {
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
