//
//  MeetingChatView.swift
//  Instant Notes
//
// "Ask this meeting": questions answered from the meeting's transcript and the note's text.
// The conversation is kept on the meeting, so it's still there next time.

import SwiftUI
import SwiftData
import MeetingMindKit

struct MeetingChatView: View {
    let artifact: MeetingArtifact
    let notesText: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var isThinking = false
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    private static let starters = [
        "What was decided?",
        "What are my action items?",
        "What's still open?",
    ]

    private var messages: [MeetingChatMessage] {
        artifact.chatMessages.sorted { $0.createdAt < $1.createdAt }
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
            .navigationTitle("Ask this meeting")
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
            Text("Answers come only from this meeting's transcript and your notes.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(Self.starters, id: \.self) { starter in
                Button(starter) { send(starter) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
    }

    private func bubble(_ message: MeetingChatMessage) -> some View {
        let isUser = message.role == MeetingChatTurn.Role.user.rawValue
        return HStack {
            if isUser { Spacer(minLength: 48) }
            Text(message.content)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(isUser ? Color.white : Color("InkColor"))
                .background(
                    isUser ? Color.accentColor : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            if !isUser { Spacer(minLength: 48) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about this meeting…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
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
        // Earlier turns go along so follow-ups like "and who owns that?" make sense.
        let history = messages.map {
            MeetingChatTurn(role: MeetingChatTurn.Role(rawValue: $0.role) ?? .user, text: $0.content)
        }
        let asked = append(.user, question)
        draft = ""
        error = nil
        isThinking = true

        let transcript = artifact.fullTranscript ?? ""
        Task {
            defer { isThinking = false }
            do {
                let answer = try await OnDeviceMeetingChat()
                    .answer(question: question, transcript: transcript, notes: notesText, history: history)
                append(.assistant, answer)
            } catch {
                // Put the question back to send again, rather than leave it unanswered in the history.
                artifact.chatMessages.removeAll { $0.id == asked.id }
                modelContext.delete(asked)
                if draft.isEmpty { draft = question }
                self.error = error.localizedDescription
            }
        }
    }

    @discardableResult
    private func append(_ role: MeetingChatTurn.Role, _ content: String) -> MeetingChatMessage {
        let message = MeetingChatMessage(artifactId: artifact.id, role: role.rawValue, content: content)
        modelContext.insert(message)
        artifact.chatMessages.append(message)
        return message
    }
}
