//
//  NoteImage.swift
//  Instant Notes
//
// A photo in a note. The note's image blocks refer to it by id; the bytes live here, out of
// the blocks JSON, so a note with photos still saves and loads its text quickly.

import Foundation
import SwiftData
import UIKit

@Model
final class NoteImage {
    var id: UUID = UUID()
    /// JPEG, at most `maxPixels` on the long side.
    @Attribute(.externalStorage) var data: Data = Data()
    var createdAt: Date = Date.now
    var note: Note?
    /// The words in the photo, read on the device so search can find them. Nil until read; empty
    /// when the photo has none.
    var recognizedText: String?

    init(id: UUID = UUID(), data: Data, createdAt: Date = .now) {
        self.id = id
        self.data = data
        self.createdAt = createdAt
    }

    /// Camera photos are 12+ MP; this is plenty for a page and for sharing.
    static let maxPixels: CGFloat = 2048

    /// Re-encodes a photo from the camera, the library or a file as a JPEG no larger than
    /// `maxPixels`.
    static func jpeg(from image: UIImage) -> Data? {
        let size = image.size
        let scale = min(1, maxPixels / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Drawing also applies the photo's orientation, so the JPEG is upright everywhere.
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
