import Foundation
import Testing

@testable import MeetingMindKit

private func layout(_ blocks: [Block]) -> [String] {
    blocks.map { block in
        let kind = switch block.type {
        case let .heading(level): "h\(level)"
        case .bulletedList: "-"
        case .quote: ">"
        default: "p"
        }
        return "\(kind) \(block.plainText)"
    }
}

@Suite("Document reader")
struct DocumentReaderTests {
    @Test("PDF lines are joined back into paragraphs, mending broken words")
    func paragraphsFromLines() {
        let lines = [
            "The committee met on Tuesday to review the budget for",
            "the coming year and agreed to fund the new library wing",
            "before the winter.",
            "",
            "Construction will start in spring once the city has signed",
            "off on the plans, and the architects expect it to take eigh-",
            "teen months.",
            "Questions go to the clerk.",
        ]
        #expect(DocumentReader.paragraphs(fromLines: lines) == [
            "The committee met on Tuesday to review the budget for the coming year and agreed to fund the new library wing before the winter.",
            "Construction will start in spring once the city has signed off on the plans, and the architects expect it to take eighteen months.",
            "Questions go to the clerk.",
        ])
        #expect(DocumentReader.paragraphs(fromLines: ["", "  "]).isEmpty)
    }

    @Test("Text files are read as UTF-8, UTF-16 or Windows Latin")
    func textEncodings() {
        #expect(DocumentReader.text(of: Data("Café crème".utf8)) == "Café crème")
        var utf16 = Data([0xFF, 0xFE])
        utf16.append("Résumé".data(using: .utf16LittleEndian)!)
        #expect(DocumentReader.text(of: utf16) == "Résumé")
        // 0x92 is a curly apostrophe in Windows-1252 and invalid on its own in UTF-8.
        #expect(DocumentReader.text(of: Data([0x69, 0x74, 0x92, 0x73])) == "it’s")
    }

    @Test("A Markdown file's heading becomes the title; a text file is titled by its name")
    func markdownAndText() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "reader-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let markdown = folder.appending(path: "notes.md")
        try "# Field guide\r\n\r\nOwls hunt at night.\r\n\r\n- Barn owl\r\n- Tawny owl\r\n".write(to: markdown, atomically: true, encoding: .utf8)
        let guide = try DocumentReader.read(markdown)
        #expect(guide.title == "Field guide")
        #expect(layout(guide.document.blocks) == ["p Owls hunt at night.", "- Barn owl", "- Tawny owl"])

        let text = folder.appending(path: "Reading list.txt")
        try "First line of the list.\n\nSecond paragraph.".write(to: text, atomically: true, encoding: .utf8)
        let list = try DocumentReader.read(text)
        #expect(list.title == "Reading list")
        #expect(layout(list.document.blocks) == ["p First line of the list.", "p Second paragraph."])
    }

    @Test("Unsupported and empty files are refused with a reason")
    func refusals() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "reader-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let docx = folder.appending(path: "report.docx")
        try Data([0x50, 0x4B]).write(to: docx)
        #expect(throws: DocumentReader.Failure.unsupported("docx")) { try DocumentReader.read(docx) }

        let empty = folder.appending(path: "empty.txt")
        try Data().write(to: empty)
        #expect(throws: DocumentReader.Failure.noText) { try DocumentReader.read(empty) }
    }

    #if canImport(AppKit) && canImport(PDFKit)
    @Test("An RTF file keeps its lines as paragraphs")
    func rtf() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "Minutes-\(UUID()).rtf")
        defer { try? FileManager.default.removeItem(at: file) }
        let text = NSAttributedString(string: "Budget approved.\nNext meeting in May.")
        let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        try data.write(to: file)
        let read = try DocumentReader.read(file)
        #expect(layout(read.document.blocks) == ["p Budget approved.", "p Next meeting in May."])
    }

    @Test("A PDF's text comes back as paragraphs, with its own title")
    func pdfText() throws {
        let file = try TestPDF.write(title: "Library proposal", pages: [.text("""
            The committee met on Tuesday to review the budget for the coming year and agreed to \
            fund the new library wing before the winter, subject to a final vote in March.

            Construction will start in spring once the city has signed off on the plans.
            """)])
        defer { try? FileManager.default.removeItem(at: file) }

        let read = try DocumentReader.read(file)
        #expect(read.title == "Library proposal")
        let paragraphs = read.document.blocks.map(\.plainText)
        #expect(paragraphs.contains { $0.contains("agreed to fund the new library wing before the winter") })
        #expect(paragraphs.last?.contains("signed off on the plans") == true)
    }

    @Test("A scanned PDF page is read with text recognition")
    func scannedPDF() throws {
        let file = try TestPDF.write(title: nil, pages: [.image("Quarterly roadmap review")])
        defer { try? FileManager.default.removeItem(at: file) }

        let read = try DocumentReader.read(file)
        #expect(read.title == file.deletingPathExtension().lastPathComponent)
        #expect(read.document.plainText.localizedCaseInsensitiveContains("roadmap"))
    }
    #endif
}

@Suite("Web page reader")
struct WebPageReaderTests {
    static let page = """
        <!doctype html>
        <html><head>
          <title>Owls | Birding Weekly</title>
          <meta property="og:title" content="How owls hunt at night &amp; why">
          <style>p { color: red; }</style>
          <script>var menu = "<div>not text</div>"; if (a < b) {}</script>
        </head>
        <body>
          <nav><a href="/">Home</a><a href="/birds">Birds</a></nav>
          <header><p>Subscribe today</p></header>
          <article>
            <h1>How owls hunt at night &amp; why</h1>
            <p>Owls hear prey under snow.<br>Their faces funnel sound.</p>
            <!-- an ad -->
            <aside><p>Related: parrots</p></aside>
            <h3>Silent flight</h3>
            <p>Soft feather edges muffle  the&nbsp;wingbeat&#8217;s noise.</p>
            <ul><li>Barn owl</li><li>Tawny&#x20;owl</li></ul>
            <blockquote>An owl is a flying ear.</blockquote>
            <figure><img src="owl.jpg"><figcaption>An owl</figcaption></figure>
          </article>
          <footer><p>© Birding Weekly</p></footer>
        </body></html>
        """

    @Test("Keeps the article: headings, paragraphs, lists and quotes, without menus or scripts")
    func article() {
        let read = WebPageReader.page(fromHTML: Self.page, url: URL(string: "https://example.com/owls")!)
        #expect(read.title == "How owls hunt at night & why")
        #expect(layout(read.document.blocks) == [
            "p Owls hear prey under snow. Their faces funnel sound.",
            "h3 Silent flight",
            "p Soft feather edges muffle the wingbeat’s noise.",
            "- Barn owl",
            "- Tawny owl",
            "> An owl is a flying ear.",
        ])
    }

    @Test("Without an article, the body is read; two line breaks part paragraphs; the title falls back to <title>")
    func body() {
        let html = "<html><head><title>Notes</title></head><body><nav>Menu</nav><p>One.</p><div>Two<br> <br>Three</div></body></html>"
        let read = WebPageReader.page(fromHTML: html, url: URL(string: "https://example.com")!)
        #expect(read.title == "Notes")
        #expect(layout(read.document.blocks) == ["p One.", "p Two", "p Three"])
    }

    @Test("A \">\" inside a quoted attribute doesn't end the tag")
    func quotedAttributes() {
        // Wikipedia keeps each footnote's wikitext, "<ref>" and all, in a data-mw attribute.
        let html = #"<body><p data-mw='{"wt":"<ref>{{Cite web}}</ref>"}' title = "a > b">Owls hunt at night.</p><p class=plain>Quietly.</p></body>"#
        let read = WebPageReader.page(fromHTML: html, url: URL(string: "https://example.com")!)
        #expect(layout(read.document.blocks) == ["p Owls hunt at night.", "p Quietly."])
    }

    @Test("Furniture marked by role or class is left out: tabs, edit links, contents and footnotes")
    func furniture() {
        // Wikipedia's mobile page, cut down. "[1]" would read as one of Quolio's own citations.
        let html = """
            <body><main>
            <ul class="minerva__tab-container"><li><a>Article</a></li><li><a>Talk</a></li></ul>
            <div role="note" class="hatnote">Not to be confused with owlets.</div>
            <p>Owls hunt at night.<sup class="mw-ref reference"><a href="#cite_note-1">[1]</a></sup></p>
            <div id="toc" role="navigation"><div class="toctitle"><h2>Contents</h2></div><ul><li>1 Flight</li></ul></div>
            <div class="mw-heading"><h2>Flight</h2><span class="mw-editsection"><a role="button"><span>edit</span></a></span></div>
            <p>Their wings are silent.</p>
            <input type="checkbox" role="button"><p>Quietly.</p>
            <ol class="mw-references references"><li><span>↑</span> Smith J (2004). Owls.</li></ol>
            <div class="printfooter">Retrieved from "https://example.com"</div>
            </main></body>
            """
        let read = WebPageReader.page(fromHTML: html, url: URL(string: "https://example.com")!)
        #expect(layout(read.document.blocks) == ["p Owls hunt at night.", "h2 Flight", "p Their wings are silent.", "p Quietly."])
    }

    @Test("Furniture whose end tag is left out is kept rather than hiding the rest of the page")
    func unclosedFurniture() {
        // HTML lets a <p> go unclosed; skipping to its end tag would skip everything after it.
        let html = #"<body><p>One.</p><p class="hatnote">See also: owlets.<p>Two.<div role="navigation">Home</div><p>Three.</body>"#
        let read = WebPageReader.page(fromHTML: html, url: URL(string: "https://example.com")!)
        #expect(layout(read.document.blocks) == ["p One.", "p See also: owlets.", "p Two.", "p Three."])
    }

    @Test("The site's name is left out of the title, and a last heading with nothing under it is dropped")
    func siteName() {
        let html = """
            <head><title>Owls - Wikipedia</title></head>
            <body><main><h1><span>Owls</span></h1><p>Owls hunt at night.</p><h2>See also</h2><p>Hawks</p>
            <h2>References</h2><ol class="mw-references"><li>Smith J (2004). Owls.</li></ol></main></body>
            """
        let read = WebPageReader.page(fromHTML: html, url: URL(string: "https://example.com")!)
        #expect(read.title == "Owls")
        #expect(layout(read.document.blocks) == ["p Owls hunt at night.", "h2 See also", "p Hawks"])
        // A title that only starts with the heading's words is kept.
        let other = WebPageReader.page(fromHTML: "<title>Owls and hawks</title><h1>Owls</h1>", url: URL(string: "https://example.com")!)
        #expect(other.title == "Owls and hawks")
    }

    @Test("Links without a scheme work; other schemes and non-links don't")
    func links() {
        #expect(WebPageReader.webURL(from: " example.com/post ")?.absoluteString == "https://example.com/post")
        #expect(WebPageReader.webURL(from: "http://example.com")?.absoluteString == "http://example.com")
        #expect(WebPageReader.webURL(from: "ftp://example.com") == nil)
        #expect(WebPageReader.webURL(from: "owls") == nil)
    }

    @Test("Named and numbered entities decode; unknown ones stay as written")
    func entities() {
        #expect(WebPageReader.decodeEntities("Tom &amp; Jerry &#8212; &#x201C;hi&#x201D; &bogus; & more") == "Tom & Jerry — “hi” &bogus; & more")
    }
}

@Suite("Notebook summary")
struct NotebookSummaryTests {
    static let digests = [
        SourceDigest(noteID: UUID(), sourceModifiedAt: .now, title: "Budget memo", summary: "The library wing is funded.", keyPoints: ["Vote in March"]),
        SourceDigest(noteID: UUID(), sourceModifiedAt: .now, title: "City plan", summary: "Building starts in spring.", keyPoints: []),
    ]

    @Test("Overview, themes, agreement and difference, then each source numbered")
    func layoutWithSources() {
        let overview = NotebookOverview(overview: "A new library wing is coming [1, 2].", themes: ["Funding [1]"],
                                        agreements: ["The wing is wanted [1, 2]"], differences: [])
        #expect(layout(NotebookSummary.blocks(overview: overview, digests: Self.digests)) == [
            "p A new library wing is coming [1, 2].",
            "h2 Key themes", "- Funding [1]",
            "h2 Where sources agree", "- The wing is wanted [1, 2]",
            "h2 Sources",
            "h3 [1] Budget memo", "p The library wing is funded.", "- Vote in March",
            "h3 [2] City plan", "p Building starts in spring.",
        ])
    }

    @Test("With one source there's nothing to compare")
    func oneSource() {
        let overview = NotebookOverview(overview: "Funded.", agreements: ["Invented"], differences: ["Invented"])
        let headings = NotebookSummary.blocks(overview: overview, digests: [Self.digests[0]]).filter {
            if case .heading = $0.type { true } else { false }
        }
        #expect(headings.map(\.plainText) == ["Sources", "[1] Budget memo"])
    }

    @Test("Citations go inside the full stop")
    func citing() {
        #expect(NotebookSummary.citing("Costs rose.", [1, 3]) == "Costs rose [1, 3].")
        #expect(NotebookSummary.citing("Funding", [2]) == "Funding [2]")
        #expect(NotebookSummary.citing("Funding", []) == "Funding")
    }

    @Test("A cited source that says nothing about the point, or doesn't exist, is dropped")
    func supportedCitations() {
        #expect(NotebookSummary.supported([2, 1, 1], text: "The wing is funded", digests: Self.digests) == [1])
        #expect(NotebookSummary.supported([1, 2], text: "Building the library wing", digests: Self.digests) == [1, 2])
        #expect(NotebookSummary.supported([3, 0], text: "The library wing", digests: Self.digests).isEmpty)
    }

    @Test("A point with a figure cites only the sources that give it")
    func supportedFigures() {
        let costs = [
            SourceDigest(noteID: UUID(), sourceModifiedAt: .now, title: "Budget memo", summary: "The wing costs $2 million.", keyPoints: []),
            SourceDigest(noteID: UUID(), sourceModifiedAt: .now, title: "City plan", summary: "The wing will cost $3 million.", keyPoints: []),
        ]
        #expect(NotebookSummary.supported([1, 2], text: "The wing costs $3 million", digests: costs) == [2])
        #expect(NotebookSummary.supported([1, 2], text: "The wing's cost", digests: costs) == [1, 2])
    }

    @Test("A difference names the thing, then what each source says")
    func difference() {
        #expect(NotebookSummary.difference("Parking fee:", [(says: "$8 a day.", sources: [1]), (says: "$10 from June", sources: [2, 3])])
                == "Parking fee: $8 a day [1]; $10 from June [2, 3].")
    }

    @Test("An overview that ends by introducing a list loses that last sentence")
    func leadIn() {
        #expect(NotebookSummary.droppingLeadIn("It covers photosynthesis. It covers the following topics: ")
                == "It covers photosynthesis.")
        #expect(NotebookSummary.droppingLeadIn("The topics are:") == "The topics are:")
        #expect(NotebookSummary.droppingLeadIn("The wing is funded. Building starts in spring.")
                == "The wing is funded. Building starts in spring.")
    }

    @Test("A difference that only says one source leaves something out isn't a disagreement")
    func omissions() {
        #expect(NotebookSummary.isOmission("Source 2 mentions the cost, while Source 1 does not mention this."))
        #expect(NotebookSummary.isOmission("Source 1 doesn't discuss permits."))
        #expect(NotebookSummary.isOmission("There is no mention of a start date in Source 2."))
        #expect(NotebookSummary.isOmission("No specific time period"))
        #expect(!NotebookSummary.isOmission("Source 1 puts the cost at $2 million; Source 2 says $3 million."))
        #expect(!NotebookSummary.isOmission("Source 1 says the vote does not need a quorum; Source 2 says it does."))
    }

    @Test("Only claims that give a figure, in digits or words, are compared")
    func figures() {
        #expect(NotebookSummary.hasFigure("$10 starting June 1"))
        #expect(NotebookSummary.hasFigure("Two million dollars from the parks budget"))
        #expect(NotebookSummary.hasFigure("A few hundred visitors"))
        #expect(!NotebookSummary.hasFigure("Some council members opposed the allocation"))
        #expect(!NotebookSummary.hasFigure("Construction starts in spring, once permits are signed"))
    }

    @Test("Each source gets an equal share of the model's budget")
    func sharedBudget() {
        let long = SourceDigest(noteID: UUID(), sourceModifiedAt: .now, title: "Long",
                                summary: Array(repeating: "word", count: 2_000).joined(separator: " "), keyPoints: [])
        let text = NotebookSummary.sourcesText([long, Self.digests[1]], wordBudget: 100)
        #expect(text.hasPrefix("[1] Long\n"))
        #expect(text.contains("[2] City plan\nBuilding starts in spring."))
        #expect(text.split(whereSeparator: \.isWhitespace).count < 120)
    }
}

@Suite("Notebook chat")
struct NotebookChatTests {
    static let memo = UUID(), plan = UUID()
    static let titles = [memo: "Budget memo", plan: "City plan"]
    static let passages =
        SearchPassage.passages(noteID: memo, title: "Budget memo", blocks: [
            Block(type: .paragraph, runs: [.plain("The council funded the library wing with two million dollars.")]),
            Block(type: .paragraph, runs: [.plain("A final vote is set for March.")]),
        ])
        + SearchPassage.passages(noteID: plan, title: "City plan", blocks: [
            Block(type: .paragraph, runs: [.plain("Construction starts in spring after permits.")]),
        ])

    @Test("Matching passages come first, numbered, from the right notes")
    func matches() {
        let sources = NotebookChat.sources(question: "When does construction start?", passages: Self.passages, titles: Self.titles)
        let first = try? #require(sources.first)
        #expect(first?.number == 1)
        #expect(first?.noteID == Self.plan && first?.title == "City plan")
        #expect(first?.text.contains("spring") == true)
        #expect(sources.map(\.number) == Array(1...sources.count))
    }

    @Test("A new question's own matches come before the last question's")
    func followUp() {
        let history = [MeetingChatTurn(role: .user, text: "When do construction and permits start in spring?")]
        let sources = NotebookChat.sources(question: "Who funded it?", history: history,
                                           passages: Self.passages, titles: Self.titles)
        #expect(sources.first?.noteID == Self.memo)
        #expect(sources.contains { $0.noteID == Self.plan })
    }

    @Test("Digests are included for broad questions, and nothing is sent twice")
    func digests() {
        let digest = SourceDigest(noteID: Self.memo, sourceModifiedAt: .now, title: "Budget memo",
                                  summary: "The wing is funded.", keyPoints: ["Vote in March"])
        let sources = NotebookChat.sources(question: "What do these have in common?", passages: Self.passages,
                                           titles: Self.titles, digests: [digest, digest])
        #expect(sources.filter { $0.text.hasPrefix("The wing is funded.") }.count == 1)
    }

    @Test("With no match, each source's opening is used")
    func openings() {
        let sources = NotebookChat.sources(question: "zzz", passages: Self.passages, titles: Self.titles)
        #expect(sources.map(\.noteID) == [Self.memo, Self.plan])
        #expect(sources[0].text.contains("library wing") && sources[0].text.contains("March"))
    }

    @Test("The budget and the limit hold")
    func budget() {
        let many = (0..<20).flatMap { i in
            SearchPassage.passages(noteID: Self.memo, title: "", blocks: [
                Block(type: .paragraph, runs: [.plain("Library item \(i) " + Array(repeating: "detail", count: 60).joined(separator: " "))]),
            ])
        }
        let sources = NotebookChat.sources(question: "library", passages: many, titles: Self.titles, wordBudget: 200, limit: 8)
        #expect(sources.count <= 8)
        #expect(sources.map { $0.text.split(whereSeparator: \.isWhitespace).count }.reduce(0, +) <= 200)
    }

    @Test("The prompt lists sources and the conversation, without old citation numbers")
    func prompt() {
        let sources = [NotebookChat.Source(number: 1, noteID: Self.plan, title: "City plan", text: "Starts in spring.")]
        let prompt = NotebookChat.prompt(question: "Why then?", sources: sources, history: [
            MeetingChatTurn(role: .user, text: "When does it start?"),
            MeetingChatTurn(role: .assistant, text: "In spring [3], after permits [1, 2]."),
        ])
        #expect(prompt.contains("[1] City plan\nStarts in spring."))
        #expect(prompt.contains("You: In spring, after permits."))
        #expect(prompt.hasSuffix("QUESTION: Why then?"))
    }

    @Test("What the sources say is kept once, with every source that says it")
    func claims() {
        let claims = NotebookChat.claims([
            (source: 1, says: "- The loop is 7.2 miles."), (source: 2, says: "the loop is 7.2 miles"),
            (source: 1, says: "The loop is 7.2 miles"), (source: 3, says: "Invented"), (source: 2, says: " - "),
            (source: 2, says: "Nothing."),
        ], count: 2)
        #expect(claims.map(\.says) == ["The loop is 7.2 miles."])
        #expect(claims.map(\.sources) == [[1, 2]])
    }

    @Test("Where sources disagree, the answer gives what each says, cited")
    func disagreement() {
        let claims = [(says: "Parking costs $8", sources: [2]), (says: "The fee is $10 from June.", sources: [1])]
        #expect(NotebookChat.answer("Parking costs $8 [2].", claims: claims, disagree: true, count: 2)
                == "The sources differ:\n- Parking costs $8 [2].\n- The fee is $10 from June [1].")
        #expect(NotebookChat.answer("Parking costs $8 [2].", claims: claims, disagree: false, count: 2) == "Parking costs $8 [2].")
    }

    @Test("An answer of only citations gives what the sources say; an uncited answer cites them")
    func answerFallbacks() {
        let claims = [(says: "The loop is 7.2 miles", sources: [1, 2]), (says: "It climbs 1,700 feet", sources: [1])]
        #expect(NotebookChat.answer("[1], [2]", claims: claims, disagree: false, count: 2)
                == "- The loop is 7.2 miles [1, 2].\n- It climbs 1,700 feet [1].")
        #expect(NotebookChat.answer("[1]", claims: [claims[1]], disagree: false, count: 2) == "It climbs 1,700 feet [1].")
        #expect(NotebookChat.answer("It's 7.2 miles.", claims: claims, disagree: false, count: 2) == "It's 7.2 miles [1, 2].")
        #expect(NotebookChat.answer("The notebook doesn't cover it.", claims: [], disagree: true, count: 2)
                == "The notebook doesn't cover it.")
    }
}

#if canImport(AppKit) && canImport(PDFKit)
import AppKit
import CoreText

/// Builds small PDFs for tests: pages of real text, or of text drawn as a picture, like a scan.
enum TestPDF {
    enum Page {
        case text(String)
        case image(String)
    }

    static func write(title: String?, pages: [Page]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Scan-\(UUID()).pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        var info: [CFString: Any] = [:]
        if let title { info[kCGPDFContextTitle] = title }
        guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { throw CocoaError(.fileWriteUnknown) }
        for page in pages {
            context.beginPDFPage(nil)
            switch page {
            case let .text(text):
                let attributed = NSAttributedString(string: text, attributes: [.font: NSFont(name: "Helvetica", size: 12)!])
                let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attributed), CFRange(),
                                                     CGPath(rect: box.insetBy(dx: 72, dy: 72), transform: nil), nil)
                CTFrameDraw(frame, context)
            case let .image(text):
                let image = NSImage(size: NSSize(width: 1200, height: 300), flipped: false) { rect in
                    NSColor.white.setFill()
                    rect.fill()
                    (text as NSString).draw(at: NSPoint(x: 40, y: 120), withAttributes: [.font: NSFont.systemFont(ofSize: 64)])
                    return true
                }
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    context.draw(cgImage, in: CGRect(x: 36, y: 500, width: 540, height: 135))
                }
            }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
}
#endif
