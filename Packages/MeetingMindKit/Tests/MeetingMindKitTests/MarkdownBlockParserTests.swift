import Foundation
import Testing

@testable import MeetingMindKit

@Suite("MarkdownBlockParser")
struct MarkdownBlockParserTests {
    @Test("A leading H1 becomes the title and is not itself a block")
    func leadingH1IsTitle() {
        let result = MarkdownBlockParser.parse("# My Page\n\nSome text.")
        #expect(result.title == "My Page")
        #expect(result.document.blocks.map(\.plainText) == ["Some text."])
    }

    @Test("No leading H1 leaves the title nil")
    func noH1LeavesTitleNil() {
        let result = MarkdownBlockParser.parse("Just a paragraph.")
        #expect(result.title == nil)
        #expect(result.document.blocks.map(\.plainText) == ["Just a paragraph."])
    }

    @Test("Headings H1-H3 after the title parse with their level")
    func headingsParseWithLevel() {
        let result = MarkdownBlockParser.parse("# Title\n\n## Section\n\n### Subsection")
        let types = result.document.blocks.map(\.type)
        #expect(types == [.heading(level: 2), .heading(level: 3)])
    }

    @Test("A blank line separates two paragraphs")
    func blankLineSeparatesParagraphs() {
        let result = MarkdownBlockParser.parse("First paragraph.\n\nSecond paragraph.")
        #expect(result.document.blocks.map(\.plainText) == ["First paragraph.", "Second paragraph."])
    }

    @Test("Soft-wrapped lines join into one paragraph")
    func softWrapJoinsParagraph() {
        let result = MarkdownBlockParser.parse("This is one\nparagraph split\nacross lines.")
        #expect(result.document.blocks.map(\.plainText) == ["This is one paragraph split across lines."])
        #expect(result.document.count == 1)
    }

    @Test("A dash, asterisk, or underscore divider becomes a divider block")
    func dividerVariants() {
        for divider in ["---", "***", "___"] {
            let result = MarkdownBlockParser.parse("Above.\n\n\(divider)\n\nBelow.")
            #expect(result.document.blocks.map(\.type) == [.paragraph, .divider, .paragraph], "divider: \(divider)")
        }
    }

    @Test("Bulleted list markers -, *, and + all parse as bulletedList")
    func bulletedListMarkers() {
        for marker in ["-", "*", "+"] {
            let result = MarkdownBlockParser.parse("\(marker) An item")
            #expect(result.document.blocks.first?.type == .bulletedList, "marker: \(marker)")
            #expect(result.document.blocks.first?.plainText == "An item")
        }
    }

    @Test("Numbered list items parse as numberedList regardless of the literal number")
    func numberedListItems() {
        let result = MarkdownBlockParser.parse("1. First\n2. Second\n5. Third")
        #expect(result.document.blocks.map(\.type) == [.numberedList, .numberedList, .numberedList])
        #expect(result.document.blocks.map(\.plainText) == ["First", "Second", "Third"])
    }

    @Test("Nested list items get an indent level from their leading spaces")
    func nestedListIndent() {
        let result = MarkdownBlockParser.parse("- Top\n    - Nested\n        - Double nested")
        #expect(result.document.blocks.map(\.indent) == [0, 1, 2])
    }

    @Test("Unchecked and checked todos parse as todo blocks with the right isChecked state")
    func todoItems() {
        let result = MarkdownBlockParser.parse("- [ ] Not done\n- [x] Done\n- [X] Also done")
        #expect(result.document.blocks.allSatisfy { $0.type == .todo })
        #expect(result.document.blocks.map(\.isChecked) == [false, true, true])
        #expect(result.document.blocks.map(\.plainText) == ["Not done", "Done", "Also done"])
    }

    @Test("A todo is not double-matched as a bulleted list item")
    func todoNotMatchedAsBullet() {
        let result = MarkdownBlockParser.parse("- [ ] A task")
        #expect(result.document.count == 1)
        #expect(result.document.blocks.first?.type == .todo)
    }

    @Test("A blockquote parses as a quote block")
    func quoteBlock() {
        let result = MarkdownBlockParser.parse("> A quoted line")
        #expect(result.document.blocks.first?.type == .quote)
        #expect(result.document.blocks.first?.plainText == "A quoted line")
    }

    @Test("A blockquote starting with an emoji parses as a callout, not a quote")
    func calloutBlock() {
        let result = MarkdownBlockParser.parse("> 💡 A helpful tip")
        #expect(result.document.blocks.first?.type == .callout(emoji: "💡"))
        #expect(result.document.blocks.first?.plainText == "A helpful tip")
    }

    @Test("A fenced code block captures its language and body verbatim")
    func codeBlockWithLanguage() {
        let result = MarkdownBlockParser.parse("```swift\nlet x = 1\nlet y = 2\n```")
        #expect(result.document.blocks.first?.type == .code(language: "swift"))
        #expect(result.document.blocks.first?.plainText == "let x = 1\nlet y = 2")
    }

    @Test("A fenced code block with no language tag has a nil language")
    func codeBlockWithoutLanguage() {
        let result = MarkdownBlockParser.parse("```\nplain text\n```")
        #expect(result.document.blocks.first?.type == .code(language: nil))
    }

    @Test("An unclosed code fence still captures everything to the end of the input")
    func unclosedCodeFence() {
        let result = MarkdownBlockParser.parse("```\nline one\nline two")
        #expect(result.document.blocks.first?.type == .code(language: nil))
        #expect(result.document.blocks.first?.plainText == "line one\nline two")
    }

    @Test("A realistic Notion export page parses into the expected block sequence")
    func realisticPage() {
        let markdown = """
        # Q3 Roadmap

        ## Decisions

        - [x] Ship without Notion sync
        - [ ] Pick default Whisper model

        > 💡 Revisit sync in v1.1

        Regular paragraph with **bold** and `code`.

        ---

        1. First step
        2. Second step
        """

        let result = MarkdownBlockParser.parse(markdown)
        #expect(result.title == "Q3 Roadmap")

        let types = result.document.blocks.map(\.type)
        #expect(types == [
            .heading(level: 2),
            .todo, .todo,
            .callout(emoji: "💡"),
            .paragraph,
            .divider,
            .numberedList, .numberedList,
        ])
    }

    // MARK: - Inline formatting

    @Test("Bold, italic, and code spans split into runs with the right attributes")
    func inlineFormattingRuns() {
        let runs = MarkdownBlockParser.runs(from: "plain **bold** *italic* `code` end")
        #expect(runs.map(\.text) == ["plain ", "bold", " ", "italic", " ", "code", " end"])
        #expect(runs[1].isBold)
        #expect(runs[3].isItalic)
        #expect(runs[5].isCode)
        #expect(!runs[0].isBold && !runs[0].isItalic && !runs[0].isCode)
    }

    @Test("Underscore italics are recognized alongside asterisk italics")
    func underscoreItalics() {
        let runs = MarkdownBlockParser.runs(from: "_italic_")
        #expect(runs == [InlineRun(text: "italic", isItalic: true)])
    }

    @Test("An unterminated marker is treated as plain text rather than dropped")
    func unterminatedMarkerIsPlainText() {
        let runs = MarkdownBlockParser.runs(from: "plain **unterminated")
        #expect(runs.map(\.text).joined() == "plain **unterminated")
        #expect(runs.allSatisfy { !$0.isBold })
    }

    @Test("Empty inline text produces no runs")
    func emptyInlineText() {
        #expect(MarkdownBlockParser.runs(from: "").isEmpty)
    }

    @Test("Underscores inside words stay literal")
    func intrawordUnderscores() {
        let runs = MarkdownBlockParser.runs(from: "Rename file_name_v2 in my_config.")
        #expect(runs == [.plain("Rename file_name_v2 in my_config.")])
    }

    @Test("Underscores in a bare URL and in a link's URL stay literal")
    func underscoresInURLs() {
        #expect(MarkdownBlockParser.runs(from: "See https://example.com/some_path_here now") == [.plain("See https://example.com/some_path_here now")])

        let runs = MarkdownBlockParser.runs(from: "Read [the docs](https://example.com/some_path_here).")
        #expect(runs == [
            .plain("Read "),
            InlineRun(text: "the docs", linkURL: URL(string: "https://example.com/some_path_here")),
            .plain("."),
        ])
    }

    @Test("Asterisks surrounded by spaces are not emphasis")
    func spacedAsterisks() {
        #expect(MarkdownBlockParser.runs(from: "2 * 3 * 4") == [.plain("2 * 3 * 4")])
    }

    @Test("A backslash makes the punctuation after it literal, and is literal before anything else")
    func backslashEscapes() {
        let runs = MarkdownBlockParser.runs(from: #"\*not italic\* \_ \\ C:\Users *a\*b*"#)
        #expect(runs == [.plain(#"*not italic* _ \ C:\Users "#), InlineRun(text: "a*b", isItalic: true)])
    }

    @Test("A link to another exported page keeps only its label")
    func relativeLinkKeepsLabel() {
        let runs = MarkdownBlockParser.runs(from: "See [Child page](Parent%20Page%20abc/Child%20page%20def.md) for more.")
        #expect(runs == [.plain("See Child page for more.")])
    }

    @Test("Images are left out of the text and counted")
    func imagesAreSkippedAndCounted() {
        let result = MarkdownBlockParser.parse("# Page\n\n![Untitled](Page%20abc/Untitled.png)\n\nBefore ![chart](Page%20abc/chart.png) after")
        #expect(result.skippedImages == 2)
        #expect(result.document.blocks.map(\.plainText) == ["Before  after"])
    }

    @Test("A Notion <aside> callout becomes one callout block with its emoji")
    func asideCallout() {
        let result = MarkdownBlockParser.parse("Intro\n<aside>\n💡 Remember this\nand this\n\n</aside>\n\nAfter")
        #expect(result.document.blocks.map(\.type) == [.paragraph, .callout(emoji: "💡"), .paragraph])
        #expect(result.document.blocks.map(\.plainText) == ["Intro", "Remember this and this", "After"])
    }

    @Test("An <aside> without a leading emoji still becomes a callout")
    func asideWithoutEmoji() {
        let result = MarkdownBlockParser.parse("<aside>\nPlain note\n</aside>")
        #expect(result.document.blocks.map(\.type) == [.callout(emoji: "💡")])
        #expect(result.document.blocks.map(\.plainText) == ["Plain note"])
    }
}
