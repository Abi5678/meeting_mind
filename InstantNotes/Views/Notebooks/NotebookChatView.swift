//
//  NotebookChatView.swift
//  Instant Notes
//
// "Ask this notebook": questions answered from a notebook's sources, citing them as [n].
// The conversation is kept with the notebook, so it's still there next time.

import SwiftUI
import SwiftData
import MeetingMindKit

struct NotebookChatView: View {
    let notebook: Notebook
    /// Opens a cited source; called just before the sheet closes.
    let open: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var isThinking = false
    @State private var error: String?

    private static let starters = [
        "What are the main points?",
        "Where do the sources agree?",
        "What's different between them?",
    ]

    private var messages: [NotebookChatMessage] {
        (notebook.chatMessages ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty { intro }
                        ForEach(messages) { message in
                            bubble(message).id(message.id)
                        }
                        if isThinking {
                            ProgressView().padding(.leading, 12).id("thinking")
                        }
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.red)
                                .id("error")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) { _, _ in scrollToEnd(proxy) }
                .onChange(of: isThinking) { _, _ in scrollToEnd(proxy) }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Ask this notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Answers come only from this notebook's sources, with a number for each one they use.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(Self.starters, id: \.self) { starter in
                Button(starter) { send(starter) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: NotebookChatMessage) -> some View {
        if message.role == MeetingChatTurn.Role.user.rawValue {
            HStack {
                Spacer(minLength: 48)
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            answer(message)
        }
    }

    private func answer(_ message: NotebookChatMessage) -> some View {
        // Renumbered as shown, so answers saved before renumbering read 1, 2, 3… too.
        let (content, sources) = NotebookChat.renumbered(message.content, sources: message.sources)
        // Several excerpts can come from one note; list each note once, with the numbers citing it.
        let cited = NotesQuestion.cited(in: content, count: sources.count)
        var notes: [(noteID: UUID, title: String, numbers: [Int])] = []
        for number in cited {
            guard let source = sources.first(where: { $0.number == number }) else { continue }
            if let index = notes.firstIndex(where: { $0.noteID == source.noteID }) {
                notes[index].numbers.append(number)
            } else {
                notes.append((source.noteID, source.title, [number]))
            }
        }
        return HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(linked(content, count: sources.count))
                    .textSelection(.enabled)
                    .foregroundStyle(Color("InkColor"))
                    .environment(\.openURL, OpenURLAction { url in
                        if let number = Int(url.host() ?? ""), let source = sources.first(where: { $0.number == number }) {
                            openNote(source.noteID)
                        }
                        return .handled
                    })
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(notes, id: \.noteID) { note in
                            Button { openNote(note.noteID) } label: {
                                HStack(spacing: 6) {
                                    Text(note.numbers.map(String.init).joined(separator: ", "))
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 6)
                                        .frame(minWidth: 22, minHeight: 22)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    Text(note.title)
                                        .font(.caption)
                                        .foregroundStyle(Color("InkColor"))
                                        .lineLimit(1)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 48)
        }
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

    private func openNote(_ id: UUID) {
        open(id)
        dismiss()
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            Text("AI-generated answers can be wrong. Tap a source number to check it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            inputField
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var inputField: some View {
        HStack(spacing: 8) {
            TextField("Ask about these sources…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .onSubmit { send(draft) }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button { send(draft) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(isThinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let target: AnyHashable? = isThinking ? "thinking" : messages.last.map { AnyHashable($0.id) }
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .bottom) }
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        guard AppleIntelligence.unavailableReason == nil, #available(iOS 26, *) else {
            error = AppleIntelligence.unavailableReason
            return
        }
        // Earlier turns go along so follow-ups make sense.
        let history = messages.map {
            MeetingChatTurn(role: MeetingChatTurn.Role(rawValue: $0.role) ?? .user, text: $0.content)
        }
        let notes = notebook.orderedSources
        let passages = notes.flatMap(\.searchPassages)
        let titles = Dictionary(notes.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let read = notebook.currentDigests
        let digests = notes.compactMap { read[$0.id] }.filter { !$0.summary.isEmpty }

        let asked = append(.user, question)
        draft = ""
        error = nil
        isThinking = true
        Task {
            defer { isThinking = false }
            do {
                let sources = await Task.detached(priority: .userInitiated) {
                    let related = RelatedWords()
                    return NotebookChat.sources(question: question, history: history, passages: passages,
                                                titles: titles, digests: digests) { related.related(to: $0) }
                }.value
                let answer = try await OnDeviceNotebookChat().answer(question: question, sources: sources, history: history)
                append(.assistant, answer, sources: sources)
            } catch {
                // Put the question back to send again, rather than leave it unanswered in the history.
                notebook.chatMessages?.removeAll { $0.id == asked.id }
                modelContext.delete(asked)
                if draft.isEmpty { draft = question }
                self.error = error.localizedDescription
            }
        }
    }

    @discardableResult
    private func append(_ role: MeetingChatTurn.Role, _ content: String, sources: [NotebookChat.Source] = []) -> NotebookChatMessage {
        let message = NotebookChatMessage(role: role.rawValue, content: content, sources: sources)
        modelContext.insert(message)
        notebook.chatMessages = (notebook.chatMessages ?? []) + [message]
        return message
    }
}
