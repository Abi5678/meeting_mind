//
//  BlockRowView.swift
//  Instant Notes
//
// One block row: a handle, the type's chrome, and the editable text, all sitting on the
// paper's ruling. Every row is a whole number of ruling lines tall, so the lines meet
// across rows and the page reads as one continuous sheet.

import SwiftUI
import MeetingMindKit

// MARK: - Metrics

/// Type sizes and the ruling pitch, scaled for the reader's Dynamic Type setting.
struct EditorMetrics {
    /// The ruling pitch. Every line of text sits on one of these.
    let pitch: CGFloat
    private let traits: UITraitCollection

    init(_ size: DynamicTypeSize) {
        let traits = UITraitCollection(preferredContentSizeCategory: Self.category(size))
        self.traits = traits
        self.pitch = UIFontMetrics(forTextStyle: .body).scaledValue(for: 30, compatibleWith: traits).rounded()
    }

    private func scaled(_ size: CGFloat) -> CGFloat {
        UIFontMetrics(forTextStyle: .body).scaledValue(for: size, compatibleWith: traits).rounded()
    }

    func font(for type: BlockType) -> UIFont {
        switch type {
        case .heading(level: 1): return .systemFont(ofSize: scaled(26), weight: .bold)
        case .heading(level: 2): return .systemFont(ofSize: scaled(22), weight: .bold)
        case .heading: return .systemFont(ofSize: scaled(19), weight: .semibold)
        case .code: return .monospacedSystemFont(ofSize: scaled(14), weight: .regular)
        default: return .systemFont(ofSize: scaled(17), weight: .regular)
        }
    }

    /// Big headings take two ruling lines, the way a title does on real ruled paper.
    func lineHeight(for type: BlockType) -> CGFloat {
        switch type {
        case .heading(level: 1), .heading(level: 2): return pitch * 2
        default: return pitch
        }
    }

    var titleFont: Font { .system(size: scaled(28), weight: .bold) }
    var chromeFont: Font { .system(size: scaled(15)) }

    private static func category(_ size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

extension EditorMetrics: Equatable {
    static func == (lhs: EditorMetrics, rhs: EditorMetrics) -> Bool { lhs.pitch == rhs.pitch }
}

/// The one set of columns the whole page lines up on.
enum EditorLayout {
    /// Where the paper's red margin rule is drawn.
    static let marginX: CGFloat = 40
    /// The slot a bullet, number, checkbox or chevron sits in.
    static let chromeWidth: CGFloat = 26
    static let leading: CGFloat = marginX + 4
    static let trailing: CGFloat = 16
    static let indentStep: CGFloat = 24
    /// The column the title, the tags and every block's text share.
    static var contentX: CGFloat { leading + chromeWidth }
}

// MARK: - Ruling

/// The paper's ruling, drawn per row rather than once behind the whole document — rows are
/// whole multiples of the pitch, so the lines join up, and a long note never has to allocate
/// one canvas the height of the page.
struct PaperRuling: View {
    let style: PaperStyle
    let pitch: CGFloat

    var body: some View {
        Canvas { context, size in
            switch style {
            case .lined:
                context.stroke(
                    horizontals(size: size, step: pitch),
                    with: .color(Color("RuleColor").opacity(0.55)),
                    lineWidth: 0.75
                )
                var margin = Path()
                margin.move(to: CGPoint(x: EditorLayout.marginX, y: 0))
                margin.addLine(to: CGPoint(x: EditorLayout.marginX, y: size.height))
                context.stroke(margin, with: .color(Self.marginRed.opacity(0.35)), lineWidth: 1)

            case .grid:
                let step = pitch / 2
                var path = horizontals(size: size, step: step)
                var x = step
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                context.stroke(path, with: .color(Color("RuleColor").opacity(0.45)), lineWidth: 0.5)

            case .dotted:
                let step = pitch / 2
                var dots = Path()
                var y = step
                while y <= size.height + 0.5 {
                    var x = step
                    while x < size.width {
                        dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                        x += step
                    }
                    y += step
                }
                context.fill(dots, with: .color(Color("RuleColor").opacity(0.6)))

            case .blank:
                break
            }
        }
        .allowsHitTesting(false)
    }

    private func horizontals(size: CGSize, step: CGFloat) -> Path {
        var path = Path()
        var y = step
        while y <= size.height + 0.5 {
            path.move(to: CGPoint(x: 0, y: y - 0.5))
            path.addLine(to: CGPoint(x: size.width, y: y - 0.5))
            y += step
        }
        return path
    }

    static let marginRed = Color(red: 0.85, green: 0.25, blue: 0.25)
}

// MARK: - Row

/// A single editable block row with the chrome its type calls for.
struct BlockRowView: View {
    let block: Block
    /// The item's number, already counted per indent level.
    let number: Int?
    let metrics: EditorMetrics
    let paper: PaperStyle
    let isFocused: Bool
    let wantsCaret: Bool
    let caretOffset: Int?
    /// Bumped by the editor on every deliberate focus move, so the caret is placed once.
    let caretGeneration: Int

    let focus: (CaretTarget?) -> Void
    let setFocused: (Bool) -> Void

    @EnvironmentObject private var state: CanvasEditorState
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: CGFloat(block.indent) * EditorLayout.indentStep, height: 0)
            if case .quote = block.type {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Self.quoteRule)
                    .frame(width: 3)
                    .frame(width: EditorLayout.chromeWidth, alignment: .leading)
                    .padding(.vertical, 3)
            } else {
                chrome
                    .frame(width: EditorLayout.chromeWidth, height: metrics.pitch)
            }
            content
        }
        .padding(.leading, EditorLayout.leading)
        .padding(.trailing, EditorLayout.trailing)
        .background(PaperRuling(style: paper, pitch: metrics.pitch))
        .overlay(alignment: .topLeading) { handle }
        .onHover { isHovering = $0 }
    }

    // MARK: Handle

    @ViewBuilder
    private var handle: some View {
        if isFocused || isHovering {
            Menu {
                Menu("Turn into") {
                    ForEach(turnIntoTypes, id: \.displayName) { type in
                        Button { state.turn(block.id, into: type) } label: {
                            Label(type.displayName, systemImage: type.iconName)
                        }
                    }
                }
                Button { state.move(block.id, by: -1) } label: { Label("Move up", systemImage: "arrow.up") }
                Button { state.move(block.id, by: 1) } label: { Label("Move down", systemImage: "arrow.down") }
                Button { state.indent(block.id, by: 1) } label: { Label("Indent", systemImage: "increase.indent") }
                Button { state.indent(block.id, by: -1) } label: { Label("Outdent", systemImage: "decrease.indent") }
                Divider()
                Button(role: .destructive) { focus(state.remove(block.id)) } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.55))
                    .frame(width: 28, height: metrics.pitch)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("Block actions")
        }
    }

    /// Divider is only worth offering on a block with nothing in it — turning written text
    /// into a rule would hide the text with no way back.
    private var turnIntoTypes: [BlockType] {
        AddBlockPicker.blockTypes.filter { $0 != .divider || block.plainText.isEmpty }
    }

    // MARK: Chrome

    @ViewBuilder
    private var chrome: some View {
        switch block.type {
        case .bulletedList:
            Circle()
                .fill(Color("InkColor").opacity(0.75))
                .frame(width: 6, height: 6)

        case .numberedList:
            Text("\(number ?? 1).")
                .font(metrics.chromeFont.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 6)

        case .todo:
            Button {
                state.updateBlock(block.id) { $0.isChecked.toggle() }
            } label: {
                Image(systemName: block.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(metrics.chromeFont)
                    .foregroundStyle(block.isChecked ? Color.accentColor : .secondary)
                    .symbolEffect(.bounce, value: block.isChecked)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: block.isChecked) { _, checked in checked }
            .accessibilityLabel(block.isChecked ? "Done" : "Not done")

        case .toggle:
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    state.updateBlock(block.id) { $0.isExpanded.toggle() }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(metrics.chromeFont.bold())
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(block.isExpanded ? 90 : 0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(block.isExpanded ? "Collapse" : "Expand")

        case .callout(let emoji):
            Text(emoji.isEmpty ? "💡" : emoji)
                .font(metrics.chromeFont)

        default:
            Color.clear
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if case .divider = block.type {
            dividerRow
        } else {
            text
                .background(blockFill)
                .overlay(blockBorder)
        }
    }

    private var text: some View {
        BlockTextView(
            text: block.plainText,
            placeholder: isFocused ? block.type.defaultPlaceholder : "",
            font: metrics.font(for: block.type),
            textColor: textColor,
            lineHeight: metrics.lineHeight(for: block.type),
            isCode: block.type.isCode,
            isFocused: isFocused,
            wantsCaret: wantsCaret,
            caretOffset: caretOffset,
            caretGeneration: caretGeneration,
            onTextChange: { state.updateText(block.id, $0) },
            onFocusChange: setFocused,
            onSplit: { lines, caret in focus(state.split(block.id, lines: lines, caret: caret)) },
            onBackspaceAtStart: { focus(state.backspaceAtStart(block.id)) },
            onIndent: { state.indent(block.id, by: $0 ? 1 : -1) }
        )
    }

    /// A divider holds no text, so it takes selection by tap instead — that is how its
    /// Delete and Turn into actions stay reachable.
    private var dividerRow: some View {
        Rectangle()
            .fill(Color("RuleColor"))
            .frame(height: 1)
            .frame(maxWidth: .infinity, minHeight: metrics.pitch, maxHeight: metrics.pitch)
            .contentShape(Rectangle())
            .onTapGesture { focus(CaretTarget(id: block.id, offset: nil)) }
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                }
            }
            .accessibilityLabel("Divider")
    }

    @ViewBuilder
    private var blockFill: some View {
        switch block.type {
        case .code:
            RoundedRectangle(cornerRadius: 6).fill(Color("InkColor").opacity(0.06))
        case .callout:
            RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.08))
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var blockBorder: some View {
        if block.type.isCode {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color("RuleColor").opacity(0.35), lineWidth: 0.5)
        }
    }

    private var textColor: UIColor {
        if block.type == .todo, block.isChecked { return .secondaryLabel }
        if case .quote = block.type { return .secondaryLabel }
        return UIColor(Color("InkColor"))
    }

    private static let quoteRule = Color(red: 0.85, green: 0.25, blue: 0.25).opacity(0.45)
}
