//
//  NotionImportCoordinator.swift
//  Instant Notes
//
// Turns a Notion export ZIP (Markdown pages + CSV databases) into pages ready to become notes.

import Foundation
import MeetingMindKit

struct NotionImportCoordinator: Sendable {
    static let shared = NotionImportCoordinator()

    private init() {}

    struct ImportedPage: Sendable {
        let title: String
        let document: BlockDocument
    }

    struct ImportResult: Sendable {
        var pages: [ImportedPage]
        /// Everything that did not become a note, so nothing is dropped silently.
        var errors: [String]

        var summary: String {
            let imported = "Imported \(pages.count) \(pages.count == 1 ? "page" : "pages")"
            return errors.isEmpty ? "\(imported)." : "\(imported), skipped \(errors.count)."
        }
    }

    struct NoPagesFound: LocalizedError {
        var errorDescription: String? {
            "No Markdown pages were found in this ZIP. In Notion, export again with the format \"Markdown & CSV\" and import that ZIP."
        }
    }

    /// Maps the archive rather than reading it into memory, and decompresses nested ZIPs one at a
    /// time; exported images are never decompressed.
    func importFromZIP(at url: URL) throws -> ImportResult {
        var result = ImportResult(pages: [], errors: [])
        try collect(from: Data(contentsOf: url, options: .alwaysMapped), into: &result)
        // An HTML or PDF export has no pages to import; don't report that as a success.
        guard !result.pages.isEmpty else { throw NoPagesFound() }
        return result
    }

    // MARK: - Helpers

    private func collect(from archive: Data, into result: inout ImportResult) throws {
        var nestedArchives: [String] = []
        let entries = try ZipArchive.entries(in: archive) { path in
            // Finder's Compress adds a binary "__MACOSX/…/._Name.md" twin for many files.
            guard !path.split(separator: "/").contains("__MACOSX"), !(path as NSString).lastPathComponent.hasPrefix("._") else {
                return false
            }
            switch (path as NSString).pathExtension.lowercased() {
            case "md", "csv": return true
            case "zip": nestedArchives.append(path); return false
            default: return false
            }
        }

        for entry in entries.sorted(by: { $0.path < $1.path }) {
            let name = (entry.path as NSString).lastPathComponent
            switch (name as NSString).pathExtension.lowercased() {
            case "md":
                guard let markdown = String(data: entry.data, encoding: .utf8) else {
                    result.errors.append("\(name): not UTF-8 text")
                    continue
                }
                let parsed = MarkdownBlockParser.parse(markdown)
                let title = parsed.title ?? Self.pageTitle(fromFilename: name)
                result.pages.append(ImportedPage(title: title, document: parsed.document))
                if parsed.skippedImages > 0 {
                    result.errors.append("\(title): \(parsed.skippedImages) \(parsed.skippedImages == 1 ? "image" : "images") not imported")
                }
            default:
                // A database's rows also export as their own .md pages, which are imported above.
                result.errors.append("\(Self.pageTitle(fromFilename: name)): database tables aren't supported yet")
            }
        }

        // Notion splits large exports into ZIPs inside the ZIP. Only one is decompressed at a time.
        for path in nestedArchives.sorted() {
            do {
                guard let nested = try ZipArchive.entries(in: archive, include: { $0 == path }).first else { continue }
                try collect(from: nested.data, into: &result)
            } catch {
                result.errors.append("\((path as NSString).lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// Notion appends a 32-character id to exported filenames: "Trip plan 1a2b…ef.md" → "Trip plan".
    static func pageTitle(fromFilename name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let stripped = base.replacingOccurrences(of: #"\s+[0-9a-f]{32}(_all)?$"#, with: "", options: .regularExpression)
        return stripped.isEmpty ? base : stripped
    }
}
