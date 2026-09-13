import Foundation

/// Parses one Notion export page (Markdown) into a `BlockDocument`.
///
/// Notion's Markdown export is not quite CommonMark: todos use `[ ]`/`[x]` at the start of a
/// list item, toggles export as a bold summary line followed by an indented nested list, and
/// callouts are a blockquote whose first character is an emoji. This parser targets exactly
/// that dialect, not general Markdown.
public enum MarkdownBlockParser {
    /// The page title Notion emits as the export's leading `# Heading`. `nil` if the source had
    /// no such line — callers fall back to the filename in that case.
    public struct Result {
        public let title: String?
        public let document: BlockDocument
    }

    public static func parse(_ markdown: String) -> Result {
        let lines = markdown.components(separatedBy: "\n")
        var document = BlockDocument()
        var title: String?
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if title == nil, let level = headingLevel(of: line), level == 1 {
                title = content(of: line, headingLevel: 1)
                index += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            if isDivider(line) {
                document.append(Block(type: .divider))
                index += 1
                continue
            }

            if let level = headingLevel(of: line) {
                document.append(Block(type: .heading(level: level), runs: runs(from: content(of: line, headingLevel: level))))
                index += 1
                continue
            }

            if let emoji = calloutEmoji(of: line) {
                let text = String(line.dropFirst(2).trimmingCharacters(in: .whitespaces).dropFirst(emoji.count))
                document.append(Block(type: .callout(emoji: emoji), runs: runs(from: text.trimmingCharacters(in: .whitespaces))))
                index += 1
                continue
            }

            if isQuote(line) {
                document.append(Block(type: .quote, runs: runs(from: quoteContent(of: line))))
                index += 1
                continue
            }

            if isCodeFence(line) {
                let language = String(line.trimmingCharacters(in: .whitespaces).dropFirst(3))
                var body: [String] = []
                index += 1
                while index < lines.count, !isCodeFence(lines[index]) {
                    body.append(lines[index])
                    index += 1
                }
                index += 1  // consume the closing fence
                document.append(Block(type: .code(language: language.isEmpty ? nil : language), runs: [.plain(body.joined(separator: "\n"))]))
                continue
            }

            if let (indent, todo) = todoItem(of: line) {
                var block = Block(type: .todo, runs: runs(from: todo.text), indent: indent)
                block.isChecked = todo.isChecked
                document.append(block)
                index += 1
                continue
            }

            if let (indent, text) = numberedListItem(of: line) {
                document.append(Block(type: .numberedList, runs: runs(from: text), indent: indent))
                index += 1
                continue
            }

            if let (indent, text) = bulletedListItem(of: line) {
                document.append(Block(type: .bulletedList, runs: runs(from: text), indent: indent))
                index += 1
                continue
            }

            // Anything else is a paragraph, possibly continued by non-blank following lines
            // (Markdown's soft-wrap rule) until a blank line or a line matching another rule.
            var paragraph = line
            var lookahead = index + 1
            while lookahead < lines.count,
                  !lines[lookahead].trimmingCharacters(in: .whitespaces).isEmpty,
                  !isStructuralLine(lines[lookahead]) {
                paragraph += " " + lines[lookahead].trimmingCharacters(in: .whitespaces)
                lookahead += 1
            }
            document.append(Block(type: .paragraph, runs: runs(from: paragraph)))
            index = lookahead
        }

        return Result(title: title, document: document)
    }

    // MARK: - Line classification

    private static func isStructuralLine(_ line: String) -> Bool {
        headingLevel(of: line) != nil
            || isDivider(line)
            || calloutEmoji(of: line) != nil
            || isQuote(line)
            || isCodeFence(line)
            || todoItem(of: line) != nil
            || numberedListItem(of: line) != nil
            || bulletedListItem(of: line) != nil
    }

    private static func headingLevel(of line: String) -> Int? {
        var count = 0
        for char in line {
            if char == "#" { count += 1 } else { break }
        }
        guard (1...3).contains(count), line.count > count, line[line.index(line.startIndex, offsetBy: count)] == " " else {
            return nil
        }
        return count
    }

    private static func content(of line: String, headingLevel: Int) -> String {
        String(line.dropFirst(headingLevel)).trimmingCharacters(in: .whitespaces)
    }

    private static func isDivider(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "---" || trimmed == "***" || trimmed == "___"
    }

    private static func isQuote(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">") && calloutEmoji(of: line) == nil
    }

    private static func quoteContent(of line: String) -> String {
        String(line.trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    /// A callout is a blockquote whose content starts with a single emoji character.
    private static func calloutEmoji(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        let body = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        guard let first = body.first, first.unicodeScalars.contains(where: { $0.properties.isEmoji && $0.properties.isEmojiPresentation }) else {
            return nil
        }
        return String(first)
    }

    private static func isCodeFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    private static func indent(of line: String) -> Int {
        let leadingSpaces = line.prefix { $0 == " " }.count
        return leadingSpaces / 4  // Notion indents nested list items by 4 spaces per level
    }

    /// `- [ ] task` or `- [x] task`, at any indent level.
    private static func todoItem(of line: String) -> (indent: Int, todo: (text: String, isChecked: Bool))? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- [ ] ", "- [x] ", "- [X] "] {
            guard trimmed.hasPrefix(prefix) else { continue }
            let text = String(trimmed.dropFirst(prefix.count))
            let isChecked = prefix.lowercased().contains("x")
            return (indent(of: line), (text, isChecked))
        }
        return nil
    }

    /// `1. item`, `2. item`, … The literal number is discarded; the block type alone conveys
    /// "numbered list," and renumbering after edits is the editor's job, not the parser's.
    private static func numberedListItem(of line: String) -> (indent: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let numberPart = trimmed[trimmed.startIndex..<dotIndex]
        guard !numberPart.isEmpty, numberPart.allSatisfy(\.isNumber) else { return nil }

        let afterDot = trimmed.index(after: dotIndex)
        guard afterDot < trimmed.endIndex, trimmed[afterDot] == " " else { return nil }
        return (indent(of: line), String(trimmed[trimmed.index(after: afterDot)...]))
    }

    private static func bulletedListItem(of line: String) -> (indent: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] {
            guard trimmed.hasPrefix(marker) else { continue }
            let rest = trimmed.dropFirst(marker.count)
            // A todo also starts with "- "; make sure we are not double-matching one here.
            guard !rest.hasPrefix("[ ] "), !rest.hasPrefix("[x] "), !rest.hasPrefix("[X] ") else { return nil }
            return (indent(of: line), String(rest))
        }
        return nil
    }

    // MARK: - Inline formatting

    /// Splits `**bold**`, `*italic*`/`_italic_`, and `` `code` `` into runs. Formatting markers
    /// cannot nest in this pass — Notion's own export rarely nests them, and a note is trivially
    /// hand-fixed after import if it does.
    static func runs(from text: String) -> [InlineRun] {
        guard !text.isEmpty else { return [] }

        enum Marker: String, CaseIterable {
            case bold = "**"
            case code = "`"
            case italicStar = "*"
            case italicUnderscore = "_"
        }

        // Longest prefix first: "**" must be tried before "*", since every "**" also matches
        // "*"'s one-character prefix. Trying only the longest matching prefix at each position
        // — and never falling through to a shorter one at the same spot — matters: bold and
        // italic-star share a leading character, so an unterminated "**foo" would otherwise let
        // the italic check reinterpret the second "*" as its own (immediately self-closing)
        // marker, silently swallowing both asterisks from the output.
        let markersByDescendingLength = Marker.allCases.sorted { $0.rawValue.count > $1.rawValue.count }

        var result: [InlineRun] = []
        var plain = ""
        let characters = Array(text)
        var i = 0

        func flushPlain() {
            if !plain.isEmpty {
                result.append(.plain(plain))
                plain = ""
            }
        }

        while i < characters.count {
            var consumed = false

            for marker in markersByDescendingLength {
                let markerChars = Array(marker.rawValue)
                guard i + markerChars.count <= characters.count,
                      Array(characters[i..<i + markerChars.count]) == markerChars else { continue }

                if let closeRange = findClosing(markerChars, in: characters, from: i + markerChars.count) {
                    flushPlain()
                    let inner = String(characters[(i + markerChars.count)..<closeRange.lowerBound])
                    var run = InlineRun(text: inner)
                    switch marker {
                    case .bold: run.isBold = true
                    case .code: run.isCode = true
                    case .italicStar, .italicUnderscore: run.isItalic = true
                    }
                    result.append(run)
                    i = closeRange.upperBound
                } else {
                    // No closing partner for the longest matching prefix: treat just its first
                    // character as literal text and re-scan from the next one.
                    plain.append(characters[i])
                    i += 1
                }
                consumed = true
                break
            }

            if !consumed {
                plain.append(characters[i])
                i += 1
            }
        }

        flushPlain()
        return result
    }

    private static func findClosing(_ marker: [Character], in characters: [Character], from start: Int) -> Range<Int>? {
        guard start < characters.count else { return nil }
        var i = start
        while i + marker.count <= characters.count {
            if Array(characters[i..<i + marker.count]) == marker {
                return i..<(i + marker.count)
            }
            i += 1
        }
        return nil
    }
}
