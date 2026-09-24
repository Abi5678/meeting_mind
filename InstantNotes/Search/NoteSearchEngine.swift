//
//  NoteSearchEngine.swift
//  Instant Notes
//
// Search across every note's text, meeting transcripts, the words in photos and handwriting, all on
// the device.

import Foundation
import SwiftData
import UIKit
import PencilKit
import MeetingMindKit

/// Holds the index and answers queries off the main thread. The caller rebuilds it only when
/// notes change (see `Note.searchSignature`), not on every keystroke.
actor NoteSearchEngine {
    private let related = RelatedWords()
    private var index = SearchIndex(passages: [])

    func rebuild(_ passages: [SearchPassage]) {
        index = SearchIndex(passages: passages)
    }

    func search(_ query: String) -> [SearchHit] {
        index.search(query) { related.related(to: $0) }
    }
}

extension Note {
    /// Changes whenever anything search reads from this note changes.
    var searchSignature: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(modifiedAt)
        hasher.combine(tags)
        hasher.combine(images?.filter { $0.recognizedText != nil }.count ?? 0)
        hasher.combine(inkText)
        hasher.combine(meetingArtifact?.segments.count ?? 0)
        return hasher.finalize()
    }

    /// What search can find in this note. Reads SwiftData, so call it on the main actor.
    var searchPassages: [SearchPassage] {
        let photoText = Dictionary((images ?? []).compactMap { image in image.recognizedText.map { (image.id, $0) } },
                                   uniquingKeysWith: { first, _ in first })
        let pieces = (meetingArtifact?.segments ?? [])
            .sorted { $0.startTime < $1.startTime }
            .map { TranscriptPiece(start: $0.startTime, end: $0.endTime, text: $0.text) }
        // Tags ride along with the title, so a tag finds its note.
        let title = ([title] + tags.map { "#\($0)" }).joined(separator: " ")
        return SearchPassage.passages(noteID: id, title: title, blocks: blockDocument.blocks, photoText: photoText,
                                      inkText: inkText, transcript: pieces, transcriptBlockText: meetingArtifact?.fullTranscript)
    }
}

/// Reads the words in photos that haven't been read yet: new photos, and ones added before
/// search could read them.
@MainActor
enum PhotoTextRecognition {
    private static var isRunning = false

    static func recognizePending(in context: ModelContext) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let pending = (try? context.fetch(FetchDescriptor<NoteImage>(predicate: #Predicate { $0.recognizedText == nil }))) ?? []
        for image in pending {
            let data = image.data
            let text = await Task.detached(priority: .utility) {
                guard let cgImage = UIImage(data: data)?.cgImage else { return "" }
                return (try? TextRecognizer.text(in: cgImage)) ?? ""
            }.value
            // Autosave writes it; saving here could beat an open editor's pending blocks to disk.
            image.recognizedText = text
        }
    }
}

/// Reads the words in notes' handwriting that hasn't been read yet: new or changed ink, and ink
/// drawn before search could read it.
@MainActor
enum InkTextRecognition {
    private static var isRunning = false
    private static var wantsRerun = false

    static func recognizePending(in context: ModelContext) async {
        // Ink that changes mid-run is picked up by one more pass rather than a second runner.
        guard !isRunning else { wantsRerun = true; return }
        isRunning = true
        defer { isRunning = false }
        repeat {
            wantsRerun = false
            let pending = (try? context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.drawingData != nil && $0.inkText == nil }))) ?? []
            for note in pending {
                guard let data = note.drawingData else { continue }
                let text = await Task.detached(priority: .utility) { read(data) }.value
                // Strokes added while reading leave it unread, for the next pass.
                guard note.modelContext != nil, note.drawingData == data else { continue }
                // Autosave writes it, as for photos.
                note.inkText = text
            }
        } while wantsRerun
    }

    /// The ink drawn dark on white, whatever the appearance (dark mode inverts black ink), and read
    /// like a photo.
    nonisolated private static func read(_ data: Data) -> String {
        guard let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return "" }
        let rect = drawing.bounds.insetBy(dx: -24, dy: -24)
        // Sharp enough to read, without a huge image for a long page.
        let scale = min(2, 4096 / max(rect.width, rect.height))
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: rect, scale: scale)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let page = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rect.size))
            ink.draw(in: CGRect(origin: .zero, size: rect.size))
        }
        guard let cgImage = page.cgImage else { return "" }
        return (try? TextRecognizer.text(in: cgImage)) ?? ""
    }
}
