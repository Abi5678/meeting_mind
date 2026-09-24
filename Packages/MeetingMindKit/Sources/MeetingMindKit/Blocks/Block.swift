import Foundation

/// One block in a note: a paragraph, heading, list item, checkbox, toggle, etc.
///
/// A block owns its inline content and its position in the outline (`indent`), but not its
/// siblings — ordering lives in `BlockDocument.blockIDs`, not in the block itself, so moving a
/// block is a array operation rather than a tree rewrite.
public struct Block: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var type: BlockType
    public var runs: [InlineRun]
    /// 0 = top level. Only meaningful for list-like types; ignored otherwise.
    public var indent: Int
    /// Only meaningful for `.toggle`; whether its children are currently shown.
    public var isExpanded: Bool
    /// Only meaningful for `.todo`; whether the checkbox is ticked.
    public var isChecked: Bool

    public init(
        id: UUID = UUID(),
        type: BlockType,
        runs: [InlineRun] = [],
        indent: Int = 0,
        isExpanded: Bool = true,
        isChecked: Bool = false
    ) {
        self.id = id
        self.type = type
        self.runs = runs
        self.indent = indent
        self.isExpanded = isExpanded
        self.isChecked = isChecked
    }

    /// The block's text with all inline formatting stripped, for search and export.
    public var plainText: String {
        runs.map(\.text).joined()
    }
}

public enum BlockType: Equatable, Sendable {
    case paragraph
    case heading(level: Int)  // 1...3; values outside that range clamp on construction sites, not here
    case bulletedList
    case numberedList
    case todo
    case toggle
    case quote
    case callout(emoji: String)
    case code(language: String?)
    case divider
    /// A photo; the image data is stored by the app under this id, not in the block.
    case image(id: UUID)
}

/// A run of inline text sharing one set of formatting attributes.
///
/// Runs are the unit of formatting, not characters — bold text is one run regardless of length,
/// which keeps the model small even for a long paragraph in mixed formatting.
public struct InlineRun: Equatable, Sendable {
    public var text: String
    public var isBold: Bool
    public var isItalic: Bool
    public var isCode: Bool
    /// Set when this run is a link; the run's `text` is the link's display text.
    public var linkURL: URL?

    public init(
        text: String,
        isBold: Bool = false,
        isItalic: Bool = false,
        isCode: Bool = false,
        linkURL: URL? = nil
    ) {
        self.text = text
        self.isBold = isBold
        self.isItalic = isItalic
        self.isCode = isCode
        self.linkURL = linkURL
    }

    /// A run with no formatting at all — the common case for imported and typed text.
    public static func plain(_ text: String) -> InlineRun {
        InlineRun(text: text)
    }
}
