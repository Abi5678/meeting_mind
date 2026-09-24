//
//  SearchHitRow.swift
//  Instant Notes
//
// One search result: which note, where in it, and the words around the match.

import SwiftUI
import MeetingMindKit

struct SearchResult: Identifiable {
    let id = UUID()
    let hit: SearchHit
}

struct SearchHitRow: View {
    let hit: SearchHit
    let noteTitle: String

    @Environment(\.modelContext) private var modelContext
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(noteTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color("InkColor"))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(place)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(snippet)
                    .font(.subheadline)
                    .foregroundStyle(Color("InkColor").opacity(0.75))
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
        .listRowSeparatorTint(Color("RuleColor"))
        .task(id: hit.passage.source) {
            if case let .photo(id) = hit.passage.source { thumbnail = NoteImageCache.image(for: id, in: modelContext) }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var symbol: String {
        switch hit.passage.source {
        case .title: "doc.text"
        case .block: "text.alignleft"
        case .transcript: "waveform"
        case .photo: "photo"
        }
    }

    /// Where in the note the match is. A transcript hit shows the moment it will play from.
    private var place: String {
        switch hit.passage.source {
        case .title: "Title"
        case .block: "Note"
        case let .transcript(start): "▶︎ " + Duration.seconds(start).formatted(.time(pattern: .minuteSecond))
        case .photo: "In photo"
        }
    }

    /// The snippet with the matched words marked like a highlighter pen.
    private var snippet: AttributedString {
        var text = AttributedString(hit.snippet)
        for range in hit.matches {
            guard let marked = Range(range, in: text) else { continue }
            text[marked].font = .subheadline.weight(.semibold)
            text[marked].foregroundColor = Color("InkColor")
            text[marked].backgroundColor = Color(red: 1.0, green: 0.93, blue: 0.45).opacity(0.6)
        }
        return text
    }
}
