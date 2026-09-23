import Compression
import Foundation
import Testing

@testable import MeetingMindKit

@Suite("ZipArchive")
struct ZipArchiveTests {
    private let page = Data(String(repeating: "# Page\n\nSome notes about photosynthesis.\n", count: 20).utf8)

    @Test("Stored and deflated entries both read back byte for byte")
    func storedAndDeflated() throws {
        let archive = TestZip.make([
            .init(path: "Export/Stored.md", content: page, deflate: false),
            .init(path: "Export/Deflated.md", content: page, deflate: true),
        ])
        let entries = try ZipArchive.entries(in: archive)
        #expect(entries.map(\.path) == ["Export/Stored.md", "Export/Deflated.md"])
        #expect(entries.allSatisfy { $0.data == page })
    }

    @Test("The include filter, directories and escaping paths are all skipped")
    func skipsFilteredDirectoriesAndEscapes() throws {
        let archive = TestZip.make([
            .init(path: "Export/", content: Data(), deflate: false),
            .init(path: "Export/photo.png", content: Data([1, 2, 3]), deflate: false),
            .init(path: "../evil.md", content: page, deflate: false),
            .init(path: "/absolute.md", content: page, deflate: false),
            .init(path: "Export/Keep.md", content: page, deflate: true),
        ])
        let entries = try ZipArchive.entries(in: archive) { $0.hasSuffix(".md") }
        #expect(entries.map(\.path) == ["Export/Keep.md"])
    }

    @Test("A stored ZIP inside a ZIP reads back from its slice of the outer archive")
    func storedNestedArchive() throws {
        let inner = TestZip.make([.init(path: "Part/Page.md", content: page, deflate: true)])
        let outer = TestZip.make([
            .init(path: "Export/Readme.md", content: page, deflate: false),
            .init(path: "Export/Part-1.zip", content: inner, deflate: false),
        ])
        let nested = try #require(try ZipArchive.entries(in: outer) { $0.hasSuffix(".zip") }.first)
        #expect(nested.data == inner)
        let entries = try ZipArchive.entries(in: nested.data)
        #expect(entries.map(\.path) == ["Part/Page.md"])
        #expect(entries.first?.data == page)
    }

    @Test("Data that is not a ZIP throws notAZip")
    func notAZip() {
        #expect(throws: ZipArchive.ReadError.notAZip) {
            try ZipArchive.entries(in: Data("hello, this is plain text and not an archive".utf8))
        }
    }

    @Test("Archives made by macOS zip and ditto read correctly, including non-ASCII names", arguments: ["zip", "ditto"])
    func realArchivers(tool: String) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("ZipArchiveTests-\(UUID().uuidString)")
        let source = root.appendingPathComponent("Export")
        try fileManager.createDirectory(at: source.appendingPathComponent("Café"), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try page.write(to: source.appendingPathComponent("Café/Résumé 1a2b.md"))
        try Data("Name,Done\nBook,Yes\n".utf8).write(to: source.appendingPathComponent("Tasks.csv"))

        let output = root.appendingPathComponent("out.zip")
        let process = Process()
        process.currentDirectoryURL = root
        if tool == "zip" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-r", "-q", "-X", output.path, "Export"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--norsrc", "--keepParent", source.path, output.path]
        }
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let entries = try ZipArchive.entries(in: Data(contentsOf: output))
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path.precomposedStringWithCanonicalMapping, $0.data) })
        #expect(byPath["Export/Café/Résumé 1a2b.md"] == page)
        #expect(byPath["Export/Tasks.csv"] == Data("Name,Done\nBook,Yes\n".utf8))
    }
}

/// Writes a minimal ZIP (no CRCs, which the reader does not check) for tests.
enum TestZip {
    struct File {
        let path: String
        let content: Data
        let deflate: Bool
    }

    static func make(_ files: [File]) -> Data {
        var local = Data()
        var central = Data()
        for file in files {
            let payload = file.deflate ? deflated(file.content) : file.content
            let name = Data(file.path.utf8)
            let offset = UInt32(local.count)
            let method: UInt16 = file.deflate ? 8 : 0

            local.append32(0x0403_4b50)
            local.append16(20); local.append16(0); local.append16(method)
            local.append16(0); local.append16(0); local.append32(0)
            local.append32(UInt32(payload.count)); local.append32(UInt32(file.content.count))
            local.append16(UInt16(name.count)); local.append16(0)
            local.append(name); local.append(payload)

            central.append32(0x0201_4b50)
            central.append16(20); central.append16(20); central.append16(0); central.append16(method)
            central.append16(0); central.append16(0); central.append32(0)
            central.append32(UInt32(payload.count)); central.append32(UInt32(file.content.count))
            central.append16(UInt16(name.count)); central.append16(0); central.append16(0)
            central.append16(0); central.append16(0); central.append32(0)
            central.append32(offset)
            central.append(name)
        }

        var archive = local
        archive.append(central)
        archive.append32(0x0605_4b50)
        archive.append16(0); archive.append16(0)
        archive.append16(UInt16(files.count)); archive.append16(UInt16(files.count))
        archive.append32(UInt32(central.count)); archive.append32(UInt32(local.count))
        archive.append16(0)
        return archive
    }

    private static func deflated(_ data: Data) -> Data {
        var output = Data(count: data.count + 64)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, data.count + 64,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        return output.prefix(written)
    }
}

private extension Data {
    mutating func append16(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
