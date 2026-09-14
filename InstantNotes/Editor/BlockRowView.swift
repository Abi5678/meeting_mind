//
//  BlockRowView.swift
//  Instant Notes
//
// Individual block row rendering based on Block.BlockType.
// Uses the "paper" design identity: warm cream, ruled lines, red margin accent.

import SwiftUI
import MeetingMindKit

/// A single editable block row with type-specific chrome (checkboxes, bullets, etc.).
struct BlockRowView: View {
    let block: Block
    @Binding var isFocused: Bool
    @State private var textContent: String
    @EnvironmentObject private var editorState: EditorDocumentState

    var body: some View {
        HStack(spacing: 0) {
            // Drag handle (visible on hover/press)
            dragHandle

            // Block-type-specific chrome
            blockChrome

            // Editable text content
            editTextContent

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .background(isFocused ? Color("PaperBackground").opacity(0.3) : .clear)
        .cornerRadius(4)
    }

    // MARK: - Drag handle

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary.opacity(0.4))
            .padding(.horizontal, 8)
            .frame(width: 24)
            .opacity(isFocused ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    // MARK: - Block-type chrome

    @ViewBuilder
    private var blockChrome: some View {
        switch block.type {
        case .bulletedList:
            Circle()
                .fill(Color("InkColor"))
                .frame(width: 6, height: 6)
                .padding(.leading, 8)

        case .numberedList:
            let currentNum = editorState.listCounters[block.id.uuidString] ?? 1
            Text("\(currentNum).")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
                .padding(.leading, 8)

        case .todo:
            Button {
                withAnimation(.spring(response: 0.3)) {
                    editorState.updateBlock(block.id) { $0.isChecked.toggle() }
                }
            } label: {
                Image(systemName: block.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(block.isChecked ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)

        case .toggle:
            Image(systemName: block.isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(block.isExpanded ? 0 : -90))
                .padding(.leading, 8)

        case .quote:
            Rectangle()
                .fill(Color("RuleColor").opacity(0.6))
                .frame(width: 3)
                .padding(.leading, 8)

        case .callout(let emoji):
            Text(emoji.isEmpty ? "💡" : emoji)
                .font(.caption)
                .padding(.trailing, 4)

        default:
            Rectangle()
                .fill(Color.clear)
                .frame(width: 24)
        }
    }

    // MARK: - Editable text

    @ViewBuilder
    private var editTextContent: some View {
        let placeholder = block.type.defaultPlaceholder

        switch block.type {
        case .code(let lang):
            TextEditor(text: $textContent)
                .font(.system(.body, design: .monospaced))
                .lineSpacing(2)
                .padding(10)
                .background(Color("InkColor").opacity(0.08).cornerRadius(6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color("RuleColor").opacity(0.3), lineWidth: 0.5)
                )
                .padding(.leading, block.type == .code ? 12 : 4)

        case .divider:
            Divider()
                .overlay(Color("RuleColor"))

        default:
            let fontSize: CGFloat = {
                switch block.type {
                case .heading(level: 1): return 28
                case .heading(level: 2): return 24
                case .heading(level: 3): return 20
                default: return 16
                }
            }()

            let fontWeight: Font.Weight = {
                if case .heading = block.type { return .bold }
                return .regular
            }()

            TextEditor(text: $textContent)
                .font(.system(size: fontSize, weight: fontWeight, design: .default))
                .lineSpacing(block.type.isHeading ? 2 : 1)
                .padding(4)
                .scrollContentBackground(.hidden)
                .background {
                    if textContent.isEmpty {
                        Text(placeholder)
                            .font(.system(size: fontSize, weight: fontWeight, design: .default))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(4)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Init

    init(block: Block, isFocused: Binding<Bool>) {
        self.block = block
        self._isFocused = isFocused
        _textContent = State(initialValue: block.plainText)
    }

    // MARK: - Paper design identity

    /// Background color matching NoteStyle Studio's warm cream paper tone.
    private var paperBgColor: Color {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return Color(uicolor: .label) // system default; paper texture applied by parent
        }
        return Color(.white)
        #else
        return Color(.white)
        #endif
    }
}
