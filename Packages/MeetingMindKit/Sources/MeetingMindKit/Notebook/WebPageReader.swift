import Foundation

/// Turns a web link into a note: the page's title and the text of its article, without the menus,
/// scripts and footers around it. A link to a PDF or a text file is read as that file.
public enum WebPageReader {
    public enum Failure: Error, LocalizedError, Equatable {
        case badLink
        case status(Int)
        case unsupported(String)
        case noText

        public var errorDescription: String? {
            switch self {
            case .badLink: "That doesn't look like a web link."
            case let .status(code): "The site answered with an error (\(code)). Check the link, or try again later."
            case let .unsupported(type): "Quolio can't read \(type) pages. Try a web article, a PDF or a text file."
            case .noText: "Quolio couldn't find any article text on that page. Pages that need you to sign in, or that build themselves with scripts, can't be read."
            }
        }
    }

    public static func read(_ link: String, session: URLSession = .shared) async throws -> ImportedDocument {
        guard let url = webURL(from: link) else { throw Failure.badLink }
        var request = URLRequest(url: url)
        // Some sites turn away requests that don't look like a browser.
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw Failure.status(status)
        }
        let name = (response.url ?? url).deletingPathExtension().lastPathComponent
        let mime = response.mimeType?.lowercased() ?? ""

        var result: ImportedDocument
        if mime == "application/pdf" || data.starts(with: Array("%PDF".utf8)) {
            result = try pdf(data, fallbackTitle: name.isEmpty ? (url.host() ?? "Web page") : name)
        } else if mime.hasPrefix("text/plain") || mime == "text/markdown" {
            result = DocumentReader.markdown(DocumentReader.text(of: data), fallbackTitle: name)
        } else if mime.isEmpty || mime.contains("html") || mime.contains("xml") {
            result = page(fromHTML: DocumentReader.text(of: data), url: response.url ?? url)
        } else {
            throw Failure.unsupported(mime)
        }
        guard !result.document.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.noText }
        // Where it came from, so the note can be traced back to the page.
        result.document.insert(Block(type: .paragraph, runs: [InlineRun(text: url.absoluteString, linkURL: url)]), after: nil)
        return result
    }

    /// "example.com/post" works as well as a full link.
    static func webURL(from link: String) -> URL? {
        var text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()),
              let host = url.host(), host.contains(".") else { return nil }
        return url
    }

    private static func pdf(_ data: Data, fallbackTitle: String) throws -> ImportedDocument {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).pdf")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        return try DocumentReader.pdf(at: file, fallbackTitle: fallbackTitle)
    }

    // MARK: - HTML

    /// Elements whose contents are never article text.
    private static let skipped: Set<String> = [
        "script", "style", "noscript", "template", "svg", "canvas", "iframe", "object",
        "nav", "header", "footer", "aside", "form", "button", "select", "figure", "menu", "dialog",
    ]
    /// The ARIA roles of elements like those above, and of footnote markers and lists.
    private static let skippedRoles: Set<String> = [
        "navigation", "banner", "contentinfo", "complementary", "search", "button", "menu", "menubar",
        "tablist", "toolbar", "dialog", "doc-noteref", "doc-endnotes",
    ]
    /// The classes Wikipedia gives its tabs, edit links, "Not to be confused with" notes, footnote
    /// markers, reference list and "Retrieved from" line.
    private static let skippedClasses: Set<Substring> = [
        "minerva__tab-container", "mw-editsection", "hatnote", "mw-ref", "mw-references", "printfooter",
    ]
    /// Elements that have no end tag.
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr",
    ]
    /// Elements that start a new block of text.
    private static let blockLevel: Set<String> = [
        "p", "div", "section", "article", "main", "h1", "h2", "h3", "h4", "h5", "h6", "li", "ul", "ol",
        "blockquote", "pre", "table", "tr", "td", "th", "dl", "dt", "dd", "figcaption", "hr",
    ]

    /// The page's title and its article as blocks: headings, paragraphs, list items and quotes.
    static func page(fromHTML html: String, url: URL) -> ImportedDocument {
        let heading = elementText("h1", in: html)
        var title = [metaContent("og:title", in: html), elementText("title", in: html), heading]
            .compactMap { $0 }.first { !$0.isEmpty } ?? url.host() ?? "Web page"
        // "Owls - Wikipedia": the page's heading is its title without the site's name.
        if let heading, !heading.isEmpty, title.count > heading.count, title.hasPrefix(heading),
           let separator = title.dropFirst(heading.count).first(where: { !$0.isWhitespace }), "-–—|·:".contains(separator) {
            title = heading
        }

        let tokens = tokens(articleHTML(html))
        var kept: Set<Int> = []
        var read = blocks(from: tokens, title: title, keeping: kept)
        // Furniture still open at the end had its end tag left out, as HTML allows for <p> and <li>:
        // read it as text rather than lose the rest of the page.
        while let unclosed = read.unclosed {
            kept.insert(unclosed)
            read = blocks(from: tokens, title: title, keeping: kept)
        }
        return ImportedDocument(title: title, document: read.document)
    }

    /// The article's blocks, and where furniture that was never closed began. Furniture at the
    /// `keeping` token indexes is read as text.
    private static func blocks(from tokens: [Token], title: String, keeping: Set<Int>) -> (document: BlockDocument, unclosed: Int?) {
        var document = BlockDocument()
        var text = ""
        var type = BlockType.paragraph
        var skipDepth = 0
        // An element marked as furniture, skipped until its end tag: nested ones of the same name count.
        var furniture: (name: String, depth: Int, start: Int)?
        var last = ""

        func flush() {
            let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            text = ""
            // The article's own title is the note's title; menus often repeat items.
            guard !clean.isEmpty, clean != last, !(document.isEmpty && clean == title) else { return }
            last = clean
            document.append(Block(type: type, runs: [.plain(clean)]))
        }

        for (index, token) in tokens.enumerated() {
            switch token {
            case let .text(chunk):
                if skipDepth == 0, furniture == nil { text += decodeEntities(chunk) }
            case let .open(name, selfClosing, isFurniture):
                if let open = furniture {
                    if name == open.name, !selfClosing { furniture?.depth += 1 }
                } else if isFurniture, !keeping.contains(index) {
                    // A void element, like <input>, has no end tag to wait for.
                    if !selfClosing, !voidElements.contains(name) { furniture = (name, 1, index) }
                } else if name == "br" {
                    // One break is a line within the paragraph; two in a row part paragraphs.
                    if text.last(where: { $0 != " " && $0 != "\t" }) == "\n" { flush() } else { text += "\n" }
                } else if skipped.contains(name) {
                    if !selfClosing { skipDepth += 1 }
                } else if skipDepth == 0, blockLevel.contains(name) {
                    flush()
                    type = blockType(for: name)
                }
            case let .close(name):
                if let open = furniture {
                    if name == open.name { furniture = open.depth > 1 ? (name, open.depth - 1, open.start) : nil }
                } else if skipped.contains(name) {
                    skipDepth = max(0, skipDepth - 1)
                } else if skipDepth == 0, blockLevel.contains(name) {
                    flush()
                    type = .paragraph
                }
            }
        }
        flush()
        // A heading with nothing under it, like "References" once its list is left out.
        while let lastID = document.order.last, case .heading? = document.blocksByID[lastID]?.type {
            _ = document.remove(lastID)
        }
        return (document, furniture?.start)
    }

    private static func blockType(for element: String) -> BlockType {
        switch element {
        case "h1", "h2": .heading(level: 2)
        case "h3", "h4", "h5", "h6": .heading(level: 3)
        case "li", "dd": .bulletedList
        case "blockquote": .quote
        default: .paragraph
        }
    }

    /// The article, or the main content, when the page marks one; otherwise the body.
    private static func articleHTML(_ html: String) -> Substring {
        for element in ["article", "main", "body"] {
            if let open = html.range(of: "<\(element)", options: .caseInsensitive),
               let close = html.range(of: "</\(element)>", options: [.caseInsensitive, .backwards]),
               open.upperBound <= close.lowerBound {
                return html[open.lowerBound ..< close.lowerBound]
            }
        }
        return html[...]
    }

    enum Token: Equatable {
        case text(Substring)
        case open(String, selfClosing: Bool, isFurniture: Bool)
        case close(String)
    }

    /// The page as text and tags, skipping comments, doctype and processing instructions.
    static func tokens(_ html: Substring) -> [Token] {
        var result: [Token] = []
        var index = html.startIndex
        while index < html.endIndex {
            guard let lt = html[index...].firstIndex(of: "<") else {
                result.append(.text(html[index...]))
                break
            }
            if lt > index { result.append(.text(html[index ..< lt])) }
            if html[lt...].hasPrefix("<!--") {
                index = html[lt...].range(of: "-->")?.upperBound ?? html.endIndex
                continue
            }
            guard let gt = tagEnd(in: html, from: lt) ?? html[lt...].firstIndex(of: ">") else { break }
            let inner = html[html.index(after: lt) ..< gt]
            index = html.index(after: gt)
            let isClose = inner.hasPrefix("/")
            let name = inner.drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }.lowercased()
            guard !name.isEmpty else { continue }  // <!doctype>, <?xml?>, or a stray "<"
            if isClose {
                result.append(.close(name))
            } else {
                result.append(.open(name, selfClosing: inner.hasSuffix("/"), isFurniture: isFurniture(inner)))
                // A script's or style's contents can hold "<" and even tags; jump to its end.
                if ["script", "style"].contains(name) {
                    let end = html[index...].range(of: "</\(name)", options: .caseInsensitive)
                    index = end?.lowerBound ?? html.endIndex
                }
            }
        }
        return result
    }

    /// The ">" that closes the tag opened at `lt`. One inside a quoted attribute value doesn't count:
    /// Wikipedia, for one, keeps footnote wikitext with "<ref>" in its attributes.
    private static func tagEnd(in html: Substring, from lt: Substring.Index) -> Substring.Index? {
        var quote: Character?
        var valueNext = false  // just past an "=", where a quoted value can start
        var index = html.index(after: lt)
        while index < html.endIndex {
            let char = html[index]
            if let open = quote {
                if char == open { quote = nil }
            } else if char == ">" {
                return index
            } else if valueNext, char == "\"" || char == "'" {
                quote = char
            }
            if !char.isWhitespace { valueNext = quote == nil && char == "=" }
            index = html.index(after: index)
        }
        return nil  // an unclosed quote; the caller falls back to the first ">"
    }

    /// Whether a tag (the text between "<" and ">") marks page furniture by its role or class.
    private static func isFurniture(_ tag: Substring) -> Bool {
        if let role = attributeValue("role", inTag: tag), skippedRoles.contains(role.lowercased()) { return true }
        return attributeValue("class", inTag: tag)?.split(whereSeparator: \.isWhitespace).contains(where: skippedClasses.contains) ?? false
    }

    /// An attribute's value in a tag's text, reading attribute by attribute, so a match inside
    /// another attribute's quoted value doesn't count.
    private static func attributeValue(_ name: String, inTag tag: Substring) -> Substring? {
        var index = tag.startIndex
        while let start = tag[index...].firstIndex(where: { !$0.isWhitespace && $0 != "/" }) {
            let end = tag[start...].firstIndex { $0.isWhitespace || $0 == "=" || $0 == "/" } ?? tag.endIndex
            let key = tag[start ..< end]
            index = end
            var value: Substring = ""
            // The value, if there is one: quoted, or up to the next space.
            if let equals = tag[end...].firstIndex(where: { !$0.isWhitespace }), tag[equals] == "=" {
                let first = tag[tag.index(after: equals)...].firstIndex { !$0.isWhitespace } ?? tag.endIndex
                if first < tag.endIndex, tag[first] == "\"" || tag[first] == "'" {
                    let open = tag.index(after: first)
                    let close = tag[open...].firstIndex(of: tag[first]) ?? tag.endIndex
                    value = tag[open ..< close]
                    index = close < tag.endIndex ? tag.index(after: close) : close
                } else {
                    let close = tag[first...].firstIndex(where: \.isWhitespace) ?? tag.endIndex
                    value = tag[first ..< close]
                    index = max(close, tag.index(after: equals))
                }
            }
            if key.lowercased() == name { return value }
        }
        return nil
    }

    private static func elementText(_ element: String, in html: String) -> String? {
        guard let open = html.range(of: "<\(element)", options: .caseInsensitive),
              let start = html[open.upperBound...].firstIndex(of: ">"),
              let close = html[start...].range(of: "</\(element)>", options: .caseInsensitive) else { return nil }
        let inner = html[html.index(after: start) ..< close.lowerBound]
        let text = tokens(inner).compactMap { if case let .text(chunk) = $0 { chunk } else { nil } }.joined()
        return decodeEntities(Substring(text)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func metaContent(_ property: String, in html: String) -> String? {
        guard let pattern = try? Regex(#"<meta\b[^>]*>"#).ignoresCase() else { return nil }
        for match in html.matches(of: pattern) {
            let tag = String(html[match.range])
            guard tag.localizedCaseInsensitiveContains("\"\(property)\"") || tag.localizedCaseInsensitiveContains("'\(property)'"),
                  let content = attribute("content", in: tag) else { continue }
            return decodeEntities(Substring(content)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let pattern = try? Regex(#"\b"# + name + #"\s*=\s*("([^"]*)"|'([^']*)')"#).ignoresCase(),
              let match = tag.firstMatch(of: pattern) else { return nil }
        let value = match.output.count > 2 ? (match.output[2].substring ?? match.output[3].substring) : nil
        return value.map(String.init)
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "mdash": "—", "ndash": "–",
        "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "copy": "©", "reg": "®",
        "trade": "™", "middot": "·", "bull": "•", "laquo": "«", "raquo": "»", "eacute": "é", "euro": "€",
    ]

    /// `&amp;`, `&#8217;` and `&#x2019;` as the characters they stand for.
    static func decodeEntities(_ text: Substring) -> String {
        guard text.contains("&") else { return String(text) }
        var result = ""
        var index = text.startIndex
        while let amp = text[index...].firstIndex(of: "&") {
            result += text[index ..< amp]
            let rest = text[text.index(after: amp)...]
            if let semicolon = rest.prefix(10).firstIndex(of: ";") {
                let name = String(rest[rest.startIndex ..< semicolon])
                var decoded: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    decoded = namedEntities[name]
                }
                if let decoded {
                    result += decoded
                    index = text.index(after: semicolon)
                    continue
                }
            }
            result += "&"
            index = text.index(after: amp)
        }
        result += text[index...]
        return result
    }
}
