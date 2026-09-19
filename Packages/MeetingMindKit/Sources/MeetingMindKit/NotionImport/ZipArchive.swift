import Foundation
import Compression

/// Reads a ZIP archive in memory. Covers what Notion and the Files app write — stored and
/// deflated entries, with or without data descriptors — but not ZIP64 or encryption.
public enum ZipArchive {
    public struct Entry: Equatable, Sendable {
        public let path: String
        public let data: Data
    }

    public enum ReadError: Error, Equatable, Sendable {
        case notAZip
        case zip64
        case encrypted(path: String)
        case unsupportedCompression(path: String, method: Int)
        case corrupt(String)
    }
}

extension ZipArchive.ReadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAZip: "This file isn't a ZIP archive."
        case .zip64: "ZIP archives over 4 GB aren't supported."
        case let .encrypted(path): "\(path) is password-protected."
        case let .unsupportedCompression(path, method): "\(path) uses unsupported compression (method \(method))."
        case let .corrupt(detail): "The archive is damaged (\(detail))."
        }
    }
}

extension ZipArchive {

    /// `include` sees each file's path before it is decompressed, so skipped entries (the images
    /// in a Notion export, say) cost nothing. Directories and paths that would escape the archive
    /// (`..`, absolute) are never returned.
    public static func entries(in archive: Data, include: (String) -> Bool = { _ in true }) throws -> [Entry] {
        let bytes = Bytes(data: archive)
        // The end-of-central-directory record is 22 bytes plus a comment of up to 65,535.
        guard let end = bytes.lastOffset(of: 0x0605_4b50, within: 22 + 65_535) else { throw ReadError.notAZip }

        let count = try bytes.u16(end + 10)
        let directoryOffset = try bytes.u32(end + 16)
        guard count != 0xFFFF, directoryOffset != 0xFFFF_FFFF else { throw ReadError.zip64 }

        var entries: [Entry] = []
        var cursor = Int(directoryOffset)
        for _ in 0..<count {
            guard try bytes.u32(cursor) == 0x0201_4b50 else { throw ReadError.corrupt("central directory") }
            let flags = try bytes.u16(cursor + 8)
            let method = Int(try bytes.u16(cursor + 10))
            // Sizes come from the central directory: with a data descriptor the local header's are zero.
            let compressedSize = Int(try bytes.u32(cursor + 20))
            let size = Int(try bytes.u32(cursor + 24))
            let nameLength = Int(try bytes.u16(cursor + 28))
            let extraLength = Int(try bytes.u16(cursor + 30))
            let commentLength = Int(try bytes.u16(cursor + 32))
            let localOffset = Int(try bytes.u32(cursor + 42))
            let path = String(decoding: try bytes.slice(cursor + 46, nameLength), as: UTF8.self)
            cursor += 46 + nameLength + extraLength + commentLength

            guard !path.hasSuffix("/"), isInsideArchive(path), include(path) else { continue }
            guard flags & 1 == 0 else { throw ReadError.encrypted(path: path) }
            guard compressedSize != 0xFFFF_FFFF, size != 0xFFFF_FFFF else { throw ReadError.zip64 }

            guard try bytes.u32(localOffset) == 0x0403_4b50 else { throw ReadError.corrupt(path) }
            let dataStart = localOffset + 30 + Int(try bytes.u16(localOffset + 26)) + Int(try bytes.u16(localOffset + 28))
            let stored = try bytes.slice(dataStart, compressedSize)
            entries.append(Entry(path: path, data: try decompress(stored, method: method, size: size, path: path)))
        }
        return entries
    }

    private static func isInsideArchive(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    private static func decompress(_ data: Data, method: Int, size: Int, path: String) throws -> Data {
        switch method {
        case 0:
            guard data.count == size else { throw ReadError.corrupt(path) }
            return Data(data)
        case 8:
            guard size > 0 else { return Data() }
            guard !data.isEmpty else { throw ReadError.corrupt(path) }
            var output = Data(count: size)
            // COMPRESSION_ZLIB is raw DEFLATE (no zlib header), which is exactly ZIP's method 8.
            let written = output.withUnsafeMutableBytes { destination in
                data.withUnsafeBytes { source in
                    compression_decode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!, size,
                        source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            guard written == size else { throw ReadError.corrupt(path) }
            return output
        default:
            throw ReadError.unsupportedCompression(path: path, method: method)
        }
    }

    /// Little-endian reads with bounds checks, so a truncated archive throws instead of trapping.
    private struct Bytes {
        let data: Data

        func slice(_ offset: Int, _ length: Int) throws -> Data {
            guard offset >= 0, length >= 0, offset + length <= data.count else { throw ReadError.corrupt("truncated") }
            let start = data.startIndex + offset
            return data[start..<start + length]
        }

        func u16(_ offset: Int) throws -> UInt16 {
            try slice(offset, 2).reversed().reduce(0) { $0 << 8 | UInt16($1) }
        }

        func u32(_ offset: Int) throws -> UInt32 {
            try slice(offset, 4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
        }

        func lastOffset(of signature: UInt32, within window: Int) -> Int? {
            guard data.count >= 22 else { return nil }
            for offset in stride(from: data.count - 22, through: max(0, data.count - window), by: -1)
            where (try? u32(offset)) == signature {
                return offset
            }
            return nil
        }
    }
}
