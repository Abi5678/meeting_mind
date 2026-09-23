import Foundation
import Testing

@testable import MeetingMindKit

@Suite("NoteMarkdownExporter")
struct NoteMarkdownExporterTests {
    @Test("Every block type survives an export and re-import")
    func roundTrip() {
        var todoDone = Block(type: .todo, runs: [.plain("Book cabin")])
        todoDone.isChecked = true
        let blocks = [
            Block(type: .heading(level: 2), runs: [.plain("Plan")]),
            Block(type: .paragraph, runs: [.plain("Hello "), InlineRun(text: "world", isBold: true)]),
            Block(type: .bulletedList, runs: [.plain("Parent")]),
            Block(type: .bulletedList, runs: [.plain("Child")], indent: 1),
            Block(type: .numberedList, runs: [.plain("First")]),
            Block(type: .numberedList, runs: [.plain("Second")]),
            todoDone,
            Block(type: .todo, runs: [.plain("Pack snacks")]),
            Block(type: .quote, runs: [.plain("Stay curious")]),
            Block(type: .callout(emoji: "💡"), runs: [.plain("Remember the charger")]),
            Block(type: .code(language: "swift"), runs: [.plain("let x = 1\nprint(x)")]),
            Block(type: .divider),
        ]

        let markdown = NoteMarkdownExporter.markdown(title: "Weekend trip", document: BlockDocument(blocks: blocks))
        let parsed = MarkdownBlockParser.parse(markdown)

        #expect(parsed.title == "Weekend trip")
        #expect(parsed.document.blocks.map(\.type) == blocks.map(\.type))
        #expect(parsed.document.blocks.map(\.plainText) == blocks.map(\.plainText))
        #expect(parsed.document.blocks.map(\.indent) == blocks.map(\.indent))
        #expect(parsed.document.blocks.map(\.isChecked) == blocks.map(\.isChecked))
        #expect(parsed.document.blocks[1].runs == blocks[1].runs)
    }

    @Test("Numbering restarts after a non-numbered block, and lists sit on adjacent lines")
    func numberingAndSpacing() {
        let blocks = [
            Block(type: .numberedList, runs: [.plain("a")]),
            Block(type: .numberedList, runs: [.plain("b")]),
            Block(type: .paragraph, runs: [.plain("break")]),
            Block(type: .numberedList, runs: [.plain("c")]),
        ]
        let markdown = NoteMarkdownExporter.markdown(title: "T", document: BlockDocument(blocks: blocks))
        #expect(markdown == "# T\n\n1. a\n2. b\n\nbreak\n\n1. c\n")
    }

    @Test("Toggles export as bullets and links keep their URL")
    func togglesAndLinks() {
        let blocks = [
            Block(type: .toggle, runs: [.plain("Details")]),
            Block(type: .paragraph, runs: [InlineRun(text: "site", linkURL: URL(string: "https://example.com"))]),
        ]
        let markdown = NoteMarkdownExporter.markdown(title: "T", document: BlockDocument(blocks: blocks))
        #expect(markdown == "# T\n\n- Details\n\n[site](https://example.com)\n")
    }

    @Test("Markdown characters in typed text survive an export and re-import")
    func markdownCharactersRoundTrip() {
        let blocks = [
            Block(type: .paragraph, runs: [.plain(#"Rename file_name_v2 to *v3* with `mv` in C:\temp\ [draft]"#)]),
            Block(type: .bulletedList, runs: [.plain("2 * 3 = 6 and __init__")]),
            Block(type: .paragraph, runs: [
                InlineRun(text: "my_docs", linkURL: URL(string: "https://example.com/some_path_here")),
                .plain(" and "),
                InlineRun(text: "snake_case", isItalic: true),
            ]),
        ]

        let markdown = NoteMarkdownExporter.markdown(title: "T", document: BlockDocument(blocks: blocks))
        #expect(markdown.contains(#"file\_name\_v2"#))

        let parsed = MarkdownBlockParser.parse(markdown)
        #expect(parsed.document.blocks.map(\.type) == blocks.map(\.type))
        #expect(parsed.document.blocks.map(\.runs) == blocks.map(\.runs))
    }
}
