//
//  AskNotesView.swift
//  Instant Notes
//
// "Ask your notes": a question answered by Apple's on-device model from the search hits for it,
// with each fact citing the note it came from. Nothing leaves the device.

import SwiftUI
import MeetingMindKit

struct AskNotesView: View {
    let question: String
    /// The search results for the question, best first.
    let results: [SearchResult]
    let titles: [UUID: String]
    /// Opens a result's note at the place it matched.
    let open: (SearchResult.ID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var answer: String?
    @State private var error: String?

    private var sources: [NotesQuestion.Source] {
        NotesQuestion.sources(from: results.map(\.hit), titles: titles)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(question)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color("InkColor"))
                    if let answer {
                        answerView(answer)
                    } else if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading your notes on this device…").foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("Ask your notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await ask() }
    }

    @ViewBuilder
    private func answerView(_ answer: String) -> some View {
        let sources = sources
        let cited = NotesQuestion.cited(in: answer, count: sources.count)
        Text(linked(answer, count: sources.count))
            .font(.body)
            .foregroundStyle(Color("InkColor"))
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                if let number = Int(url.host() ?? ""), let source = sources.first(where: { $0.number == number }) {
                    openSource(source)
                }
                return .handled
            })

        // What the answer cites, or, when it cites nothing, where the model looked.
        let shown = cited.isEmpty ? sources : cited.compactMap { number in sources.first { $0.number == number } }
        VStack(alignment: .leading, spacing: 4) {
            Text(cited.isEmpty ? "Closest matches" : "Sources")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            ForEach(shown, id: \.number) { source in
                Button { openSource(source) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(source.number)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor.opacity(0.12), in: Circle())
                            .padding(.top, 12)
                        SearchHitRow(hit: source.hit, noteTitle: source.noteTitle)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        Label("Answered on this device from your notes. Check the sources for anything important.",
              systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// The answer with each cited number as a tappable link to its source.
    private func linked(_ answer: String, count: Int) -> AttributedString {
        var text = AttributedString()
        var rest = answer.startIndex
        for citation in NotesQuestion.citations(in: answer, count: count) {
            text += AttributedString(answer[rest ..< citation.range.lowerBound])
            for number in citation.numbers {
                var link = AttributedString("[\(number)]")
                link.link = URL(string: "source://\(number)")
                link.foregroundColor = .accentColor
                link.font = .body.weight(.semibold)
                text += link
            }
            rest = citation.range.upperBound
        }
        text += AttributedString(answer[rest...])
        return text
    }

    private func openSource(_ source: NotesQuestion.Source) {
        guard let result = results.first(where: { $0.hit == source.hit }) else { return }
        open(result.id)
        dismiss()
    }

    private func ask() async {
        guard answer == nil else { return }
        guard AppleIntelligence.unavailableReason == nil, #available(iOS 26, *) else {
            error = AppleIntelligence.unavailableReason
            return
        }
        do {
            answer = try await OnDeviceNotesAnswerer().answer(question: question, sources: sources)
        } catch {
            self.error = "Couldn't answer that on this device. \(error.localizedDescription)"
        }
    }
}
