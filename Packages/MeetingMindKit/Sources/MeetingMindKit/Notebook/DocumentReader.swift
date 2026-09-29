import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A document brought into a notebook as a note: a PDF, a web page, or a text, Markdown or RTF file.
public struct ImportedDocument: Sendable {
    public var title: String
    public var document: BlockDocument

    public init(title: String, document: BlockDocument) {
        self.title = title
        self.document = document
    }
}

/// Reads documents on disk into note blocks, on the device.
public enum DocumentReader {
    public enum Failure: Error, LocalizedError, Equatable {
        case unsupported(String)
        case unreadable
        case noText

        public var errorDescription: String? {
            switch self {
            case let .unsupported(kind): "Quolio can't read .\(kind) files. Try a PDF, or a text, Markdown or RTF file."
            case .unreadable: "That file couldn't be opened."
            case .noText: "There's no text in that document to add."
            }
        }
    }

    /// Reads a PDF, text, Markdown or RTF file. A long or scanned PDF takes a while, so call it off
    /// the main actor.
    public static func read(_ url: URL) throws -> ImportedDocument {
        let name = url.deletingPathExtension().lastPathComponent
        let kind = url.pathExtension.lowercased()
        let result: ImportedDocument
        switch kind {
        case "pdf":
            result = try pdf(at: url, fallbackTitle: name)
        case "md", "markdown", "txt", "text":
            result = markdown(text(of: try Data(contentsOf: url)), fallbackTitle: name)
        case "rtf":
            result = markdown(try rtfText(at: url), fallbackTitle: name)
        default:
            throw Failure.unsupported(kind)
        }
        guard !result.document.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.noText }
        return result
    }

    /// Markdown, and plain text read as Markdown: blank lines part paragraphs, and "- " lines are lists.
    static func markdown(_ text: String, fallbackTitle: String) -> ImportedDocument {
        let parsed = MarkdownBlockParser.parse(text.replacingOccurrences(of: "\r\n", with: "\n"))
        return ImportedDocument(title: parsed.title ?? fallbackTitle, document: parsed.document)
    }

    /// UTF-8 for most files, UTF-16 when it says so up front, and Windows Latin for the rest.
    static func text(of data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    private static func rtfText(at url: URL) throws -> String {
        #if canImport(UIKit) || canImport(AppKit)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: NSAttributedString.DocumentType.rtf]
        guard let text = try? NSAttributedString(url: url, options: options, documentAttributes: nil).string else {
            throw Failure.unreadable
        }
        // Keep RTF's own line breaks as paragraphs rather than joining them like soft-wrapped text.
        return text.replacingOccurrences(of: "\n", with: "\n\n")
        #else
        throw Failure.unsupported("rtf")
        #endif
    }

    // MARK: - PDF

    #if canImport(PDFKit)
    static func pdf(at url: URL, fallbackTitle: String) throws -> ImportedDocument {
        guard let pdf = PDFDocument(url: url) else { throw Failure.unreadable }
        return read(pdf, fallbackTitle: fallbackTitle)
    }

    static func read(_ pdf: PDFDocument, fallbackTitle: String) -> ImportedDocument {
        var document = BlockDocument()
        for index in 0 ..< pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            var lines = (page.string ?? "").components(separatedBy: .newlines)
            // A scanned page has no text layer; read it like a photo.
            if lines.joined().trimmingCharacters(in: .whitespaces).count < 20, let scanned = recognizedText(on: page) {
                lines = scanned.components(separatedBy: .newlines)
            }
            for paragraph in paragraphs(fromLines: lines) {
                document.append(Block(type: .paragraph, runs: [.plain(paragraph)]))
            }
        }
        let title = (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ImportedDocument(title: title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle, document: document)
    }

    private static func recognizedText(on page: PDFPage) -> String? {
        #if canImport(Vision)
        let bounds = page.bounds(for: .mediaBox)
        // About 200 dpi: sharp enough to read, without a huge image.
        let scale = min(3, 2400 / max(bounds.width, bounds.height, 1))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard let image = page.thumbnail(of: size, for: .mediaBox).cgImageForReading else { return nil }
        return try? TextRecognizer.text(in: image)
        #else
        return nil
        #endif
    }
    #else
    static func pdf(at url: URL, fallbackTitle: String) throws -> ImportedDocument {
        throw Failure.unsupported("pdf")
    }
    #endif

    /// A PDF's text comes as the lines on the page. They're joined back into paragraphs: a line
    /// well short of the others ends one (the last line of a paragraph rarely fills the width), as
    /// does a blank line, and a word broken with a hyphen at a line end is mended.
    static func paragraphs(fromLines rawLines: [String]) -> [String] {
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }
        let lengths = lines.map(\.count).filter { $0 > 0 }.sorted()
        guard !lengths.isEmpty else { return [] }
        // The typical full line, from the longer half, so short headings don't drag it down.
        let full = lengths[lengths.count * 3 / 4]

        var paragraphs: [String] = []
        var current = ""
        func flush() {
            let text = current.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { paragraphs.append(text) }
            current = ""
        }
        for line in lines {
            guard !line.isEmpty else { flush(); continue }
            if current.hasSuffix("-"), let first = line.first, first.isLowercase {
                current.removeLast()
                current += line
            } else {
                current += current.isEmpty ? line : " " + line
            }
            if Double(line.count) < Double(full) * 0.7 { flush() }
        }
        flush()
        return paragraphs
    }
}

#if canImport(UIKit)
private extension UIImage {
    var cgImageForReading: CGImage? { cgImage }
}
#elseif canImport(AppKit)
private extension NSImage {
    var cgImageForReading: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
}
#endif
