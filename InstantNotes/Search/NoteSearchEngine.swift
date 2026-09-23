//
//  NoteSearchEngine.swift
//  Instant Notes
//
// Search across every note's text, meeting transcripts and the words in photos, all on the device.

import Foundation
import SwiftData
import UIKit
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
                                      transcript: pieces, transcriptBlockText: meetingArtifact?.fullTranscript)
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
