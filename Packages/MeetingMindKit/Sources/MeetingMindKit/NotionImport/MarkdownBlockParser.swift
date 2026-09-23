import Foundation

/// Parses one Notion export page (Markdown) into a `BlockDocument`.
///
/// Notion's Markdown export is not quite CommonMark: todos use `[ ]`/`[x]` at the start of a
/// list item, toggles export as a bold summary line followed by an indented nested list, and
/// callouts are an `<aside>` element (or, in this app's own export, a blockquote whose first
/// character is an emoji). This parser targets exactly that dialect, not general Markdown.
public enum MarkdownBlockParser {
    /// The page title Notion emits as the export's leading `# Heading`. `nil` if the source had
    /// no such line — callers fall back to the filename in that case.
    public struct Result {
        public let title: String?
        public let document: BlockDocument
        /// `![alt](path)` images left out of `document`, so the caller can report them.
        public let skippedImages: Int
    }

    public static func parse(_ markdown: String) -> Result {
        let lines = markdown.components(separatedBy: "\n")
        var document = BlockDocument()
        var title: String?
        var skippedImages = 0
        var index = 0

        func inline(_ text: String) -> [InlineRun] {
            runs(from: text, imageCount: &skippedImages)
        }

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
                document.append(Block(type: .heading(level: level), runs: inline(content(of: line, headingLevel: level))))
                index += 1
                continue
            }

            if let emoji = calloutEmoji(of: line) {
                let text = String(line.dropFirst(2).trimmingCharacters(in: .whitespaces).dropFirst(emoji.count))
                document.append(Block(type: .callout(emoji: emoji), runs: inline(text.trimmingCharacters(in: .whitespaces))))
                index += 1
                continue
            }

            if isAsideOpening(line) {
                // Notion writes a callout as `<aside>`, then its emoji and text, then `</aside>`.
                var body: [String] = []
                index += 1
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces) != "</aside>" {
                    let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { body.append(trimmed) }
                    index += 1
                }
                index += 1  // consume `</aside>`
                var text = body.joined(separator: " ")
                let emoji = leadingEmoji(of: text)
                if emoji != nil { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
                document.append(Block(type: .callout(emoji: emoji ?? "💡"), runs: inline(text)))
                continue
            }

            if isQuote(line) {
                document.append(Block(type: .quote, runs: inline(quoteContent(of: line))))
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
                var block = Block(type: .todo, runs: inline(todo.text), indent: indent)
                block.isChecked = todo.isChecked
                document.append(block)
                index += 1
                continue
            }

            if let (indent, text) = numberedListItem(of: line) {
                document.append(Block(type: .numberedList, runs: inline(text), indent: indent))
                index += 1
                continue
            }

            if let (indent, text) = bulletedListItem(of: line) {
                document.append(Block(type: .bulletedList, runs: inline(text), indent: indent))
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
            let paragraphRuns = inline(paragraph)
            // A line that held only images has nothing left to show.
            if !paragraphRuns.map(\.text).joined().trimmingCharacters(in: .whitespaces).isEmpty {
                document.append(Block(type: .paragraph, runs: paragraphRuns))
            }
            index = lookahead
        }

        return Result(title: title, document: document, skippedImages: skippedImages)
    }

    // MARK: - Line classification

    private static func isStructuralLine(_ line: String) -> Bool {
        headingLevel(of: line) != nil
            || isDivider(line)
            || calloutEmoji(of: line) != nil
            || isAsideOpening(line)
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
        return leadingEmoji(of: trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
    }

    private static func leadingEmoji(of text: String) -> String? {
        guard let first = text.first, first.unicodeScalars.contains(where: { $0.properties.isEmoji && $0.properties.isEmojiPresentation }) else {
            return nil
        }
        return String(first)
    }

    private static func isAsideOpening(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "<aside>"
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

    /// Splits `**bold**`, `*italic*`/`_italic_`, `` `code` `` and `[links](url)` into runs.
    /// Emphasis follows CommonMark's flanking rules, so `file_name_v2`, `2 * 3` and underscores in
    /// URLs stay literal, and a backslash makes the punctuation after it literal. Overlapping
    /// markers are not resolved the CommonMark way — Notion's own export rarely nests them, and
    /// a note is trivially hand-fixed after import if it does.
    static func runs(from text: String) -> [InlineRun] {
        var imageCount = 0
        return runs(from: text, imageCount: &imageCount)
    }

    /// Adds the number of `![alt](path)` images it leaves out to `imageCount`.
    private static func runs(from text: String, imageCount: inout Int) -> [InlineRun] {
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

        // Unformatted runs (a page link's label, say) join the surrounding text.
        func append(_ run: InlineRun) {
            if run == .plain(run.text) {
                plain += run.text
            } else {
                flushPlain()
                result.append(run)
            }
        }

        while i < characters.count {
            if characters[i] == "\\", i + 1 < characters.count, isEscapable(characters[i + 1]) {
                plain.append(characters[i + 1])
                i += 2
                continue
            }

            // Only web links keep their URL: a link to another page of the export points nowhere
            // once imported, so it keeps just its label. Images are left out and counted.
            let isImage = characters[i] == "!" && i + 1 < characters.count && characters[i + 1] == "["
            if isImage || characters[i] == "[", let link = link(in: characters, at: isImage ? i + 1 : i) {
                if isImage {
                    imageCount += 1
                } else {
                    var url = URL(string: link.destination)
                    if !["http", "https"].contains(url?.scheme?.lowercased()) { url = nil }
                    for var run in runs(from: link.label, imageCount: &imageCount) {
                        run.linkURL = url
                        append(run)
                    }
                }
                i = link.end
                continue
            }

            var consumed = false

            for marker in markersByDescendingLength {
                let markerChars = Array(marker.rawValue)
                guard i + markerChars.count <= characters.count,
                      Array(characters[i..<i + markerChars.count]) == markerChars else { continue }

                // Searching from one past the marker rules out empty spans like "****".
                if marker == .code || flanking(at: i, in: characters).canOpen,
                   let closeRange = findClosing(markerChars, in: characters, from: i + markerChars.count + 1) {
                    let inner = String(characters[(i + markerChars.count)..<closeRange.lowerBound])
                    if marker == .code {
                        append(InlineRun(text: inner, isCode: true))
                    } else {
                        // Parsed again so escapes, links and other markers inside still apply.
                        for var run in runs(from: inner, imageCount: &imageCount) {
                            if marker == .bold { run.isBold = true } else { run.isItalic = true }
                            append(run)
                        }
                    }
                    i = closeRange.upperBound
                } else {
                    // The longest matching prefix can't open here or has no closing partner:
                    // treat just its first character as literal text and re-scan from the next one.
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
        let isCode = marker == ["`"]
        var i = start
        while i + marker.count <= characters.count {
            // Backslash escapes don't apply inside code spans.
            if !isCode, characters[i] == "\\", i + 1 < characters.count, isEscapable(characters[i + 1]) {
                i += 2
                continue
            }
            if Array(characters[i..<i + marker.count]) == marker, isCode || flanking(at: i, in: characters).canClose {
                return i..<(i + marker.count)
            }
            i += 1
        }
        return nil
    }

    /// CommonMark's flanking rules for the run of `*` or `_` around `index`: an opener must be
    /// followed by text and a closer preceded by it, and an underscore inside a word does neither.
    private static func flanking(at index: Int, in characters: [Character]) -> (canOpen: Bool, canClose: Bool) {
        let marker = characters[index]
        var start = index, end = index
        while start > 0, characters[start - 1] == marker { start -= 1 }
        while end < characters.count, characters[end] == marker { end += 1 }
        // The start and end of the text count as whitespace.
        let before: Character = start > 0 ? characters[start - 1] : " "
        let after: Character = end < characters.count ? characters[end] : " "
        let isPunctuation = { (character: Character) in character.isPunctuation || character.isSymbol }

        let leftFlanking = !after.isWhitespace && (!isPunctuation(after) || before.isWhitespace || isPunctuation(before))
        let rightFlanking = !before.isWhitespace && (!isPunctuation(before) || after.isWhitespace || isPunctuation(after))
        guard marker == "_" else { return (leftFlanking, rightFlanking) }
        return (leftFlanking && (!rightFlanking || isPunctuation(before)), rightFlanking && (!leftFlanking || isPunctuation(after)))
    }

    /// CommonMark lets a backslash escape any ASCII punctuation character.
    private static func isEscapable(_ character: Character) -> Bool {
        character.isASCII && (character.isPunctuation || character.isSymbol)
    }

    /// `[label](destination)` with its `[` at `start`. Brackets and parentheses may nest, so a
    /// page titled "Plan [v2]" or a URL ending in "_(disambiguation)" still parses.
    private static func link(in characters: [Character], at start: Int) -> (label: String, destination: String, end: Int)? {
        guard let labelEnd = closingBracket(in: characters, from: start),
              labelEnd + 1 < characters.count, characters[labelEnd + 1] == "(",
              let destinationEnd = closingBracket(in: characters, from: labelEnd + 1) else { return nil }
        let label = String(characters[(start + 1)..<labelEnd])
        let destination = String(characters[(labelEnd + 2)..<destinationEnd]).trimmingCharacters(in: .whitespaces)
        return (label, destination, destinationEnd + 1)
    }

    /// The index of the `]` or `)` that closes the `[` or `(` at `start`, skipping escaped ones.
    private static func closingBracket(in characters: [Character], from start: Int) -> Int? {
        let open = characters[start]
        let close: Character = open == "[" ? "]" : ")"
        var depth = 0
        var i = start
        while i < characters.count {
            if characters[i] == "\\" {
                i += 2
                continue
            }
            if characters[i] == open { depth += 1 }
            if characters[i] == close {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }
}
