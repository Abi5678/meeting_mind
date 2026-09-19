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

    /// Reads the whole archive into memory, which is fine for text exports; exported images are
    /// never decompressed.
    func importFromZIP(at url: URL) throws -> ImportResult {
        var result = ImportResult(pages: [], errors: [])
        try collect(from: Data(contentsOf: url), into: &result)
        return result
    }

    // MARK: - Helpers

    private func collect(from archive: Data, into result: inout ImportResult) throws {
        let entries = try ZipArchive.entries(in: archive) { path in
            ["md", "csv", "zip"].contains((path as NSString).pathExtension.lowercased())
        }

        for entry in entries.sorted(by: { $0.path < $1.path }) {
            let name = (entry.path as NSString).lastPathComponent
            switch (name as NSString).pathExtension.lowercased() {
            case "zip":
                // Notion splits large exports into ZIPs inside the ZIP.
                do {
                    try collect(from: entry.data, into: &result)
                } catch {
                    result.errors.append("\(name): \(error.localizedDescription)")
                }
            case "md":
                guard let markdown = String(data: entry.data, encoding: .utf8) else {
                    result.errors.append("\(name): not UTF-8 text")
                    continue
                }
                let parsed = MarkdownBlockParser.parse(markdown)
                result.pages.append(ImportedPage(title: parsed.title ?? Self.pageTitle(fromFilename: name), document: parsed.document))
            default:
                // A database's rows also export as their own .md pages, which are imported above.
                result.errors.append("\(Self.pageTitle(fromFilename: name)): database tables aren't supported yet")
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
