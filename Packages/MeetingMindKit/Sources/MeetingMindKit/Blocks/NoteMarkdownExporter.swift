import Foundation

/// Writes a note as Markdown in the dialect `MarkdownBlockParser` reads, so an exported note
/// imports back as the same blocks. Toggles have no Markdown form and export as bullets.
public enum NoteMarkdownExporter {
    public static func markdown(title: String, document: BlockDocument) -> String {
        var output = "# \(title)"
        var previous: Block?
        var number = 0

        for block in document.blocks {
            number = block.type == .numberedList ? number + 1 : 0
            // Consecutive list items stay on adjacent lines; everything else is its own paragraph.
            let isListRun = previous.map { isListItem($0) && isListItem(block) } ?? false
            output += (isListRun ? "\n" : "\n\n") + line(for: block, number: number)
            previous = block
        }
        return output + "\n"
    }

    private static func isListItem(_ block: Block) -> Bool {
        [BlockType.bulletedList, .numberedList, .todo, .toggle].contains(block.type)
    }

    private static func line(for block: Block, number: Int) -> String {
        let text = inline(block.runs)
        let indent = String(repeating: " ", count: block.indent * 4)

        switch block.type {
        case .paragraph:
            return text
        case let .heading(level):
            return String(repeating: "#", count: min(max(level, 1), 3)) + " " + text
        case .bulletedList, .toggle:
            return indent + "- " + text
        case .numberedList:
            return indent + "\(number). " + text
        case .todo:
            return indent + (block.isChecked ? "- [x] " : "- [ ] ") + text
        case .quote:
            return "> " + text.replacingOccurrences(of: "\n", with: "\n> ")
        case let .callout(emoji):
            return "> \(emoji) " + text
        case let .code(language):
            return "```\(language ?? "")\n\(block.plainText)\n```"
        case .divider:
            return "---"
        }
    }

    private static func inline(_ runs: [InlineRun]) -> String {
        runs.map { run in
            guard !run.text.isEmpty else { return "" }
            var text = run.text
            if run.isCode {
                text = "`\(text)`"
            } else {
                if run.isItalic { text = "*\(text)*" }
                if run.isBold { text = "**\(text)**" }
            }
            if let url = run.linkURL { text = "[\(text)](\(url.absoluteString))" }
            return text
        }
        .joined()
    }
}
