//
//  QuizView.swift
//  Instant Notes
//
// "Quiz me": Gemini turns the open note into a multiple-choice quiz, played one card at a time.

import SwiftUI
import MeetingMindKit

struct QuizView: View {
    let noteTitle: String
    let notesText: String

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var index = 0
    @State private var picked: Int?
    @State private var results: [Bool] = []
    @State private var shake = 0
    @State private var showSettings = false

    enum Phase {
        case loading
        case failed(message: String, fix: Fix)
        case playing(Quiz)
        case finished(Quiz)
    }

    /// What the failure card offers. Retrying thin notes can't work: the snapshot is fixed while the quiz is open.
    enum Fix { case addKey, retry, backToNote }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.pink.opacity(0.18), .orange.opacity(0.10), .purple.opacity(0.15)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            switch phase {
            case .loading: LoadingCard()
            case let .failed(message, fix): failure(message, fix: fix)
            case let .playing(quiz): playing(quiz)
            case let .finished(quiz): ResultsCard(quiz: quiz, results: results, onRetry: { Task { await load() } }, onDone: { dismiss() })
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.leading, 16)
            .accessibilityLabel("Close quiz")
        }
        .sheet(isPresented: $showSettings, onDismiss: { Task { await load() } }) {
            NavigationStack { AISettingsView() }
        }
        .task { await load() }
    }

    // MARK: - Loading

    private func load() async {
        phase = .loading
        index = 0
        picked = nil
        results = []

        guard let key = GeminiKey.current else {
            phase = .failed(message: "Add your free Gemini API key to turn notes into quizzes.", fix: .addKey)
            return
        }
        let model = UserDefaults.standard.string(forKey: "gemini_model") ?? "gemini-3.8-flash"
        let client = GeminiClient(apiKey: key, configuration: .init(model: model))
        let notes = "\(noteTitle)\n\n\(notesText)"

        do {
            let quiz = try await client.generateQuiz(fromNotes: notesText.isBlank ? "" : notes)
            withAnimation(.spring) { phase = .playing(quiz) }
        } catch {
            let fix: Fix = switch error {
            case GeminiError.http(status: 400..<404, _): .addKey
            case GeminiError.emptyNotes, GeminiError.notEnoughContent: .backToNote
            default: .retry
            }
            phase = .failed(message: error.localizedDescription, fix: fix)
        }
    }

    // MARK: - Playing

    private func playing(_ quiz: Quiz) -> some View {
        let question = quiz.questions[index]
        let isLast = index == quiz.questions.count - 1

        // Scrolls so a long prompt or explanation still fits landscape and small phones; Next stays pinned below.
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    ProgressDots(total: quiz.questions.count, results: results, current: index)
                        .padding(.top, 56)
                        .id("top")

                    Text(quiz.title.uppercased())
                        .font(.caption.weight(.heavy))
                        .tracking(1.5)
                        .foregroundStyle(.pink)

                    Text(question.prompt)
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .id("prompt-\(index)")
                        .transition(.push(from: .trailing))

                    VStack(spacing: 10) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { offset, option in
                            OptionButton(
                                letter: ["A", "B", "C", "D", "E", "F"][offset % 6],
                                text: option,
                                tint: OptionButton.tints[offset % OptionButton.tints.count],
                                state: optionState(offset, answer: question.answerIndex)
                            ) { pick(offset, answer: question.answerIndex) }
                            .modifier(Shake(amount: picked == offset && offset != question.answerIndex ? CGFloat(shake) : 0))
                        }
                    }
                    .id("options-\(index)")

                    if let picked {
                        let correct = picked == question.answerIndex
                        VStack(alignment: .leading, spacing: 6) {
                            Text(correct ? ["Nailed it! 🎉", "Big brain! 🧠", "Yes! ✨"][index % 3] : "Not quite 🤏")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                            Text(question.explanation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background((correct ? Color.green : Color.orange).opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id("explanation")
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: index) { proxy.scrollTo("top", anchor: .top) }
            .onChange(of: picked) {
                // The explanation lands below the options, which in landscape is off screen.
                if picked != nil { withAnimation { proxy.scrollTo("explanation", anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 18) {
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    if isLast {
                        phase = .finished(quiz)
                    } else {
                        index += 1
                        picked = nil
                    }
                }
            } label: {
                Text(isLast ? "See my score" : "Next")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.pink, in: Capsule())
                    .foregroundStyle(.white)
            }
            .opacity(picked == nil ? 0 : 1)
            .disabled(picked == nil)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .sensoryFeedback(trigger: results) { _, new in
            guard let last = new.last else { return nil }
            return last ? .success : .error
        }
    }

    private func optionState(_ offset: Int, answer: Int) -> OptionButton.State {
        guard let picked else { return .idle }
        if offset == answer { return .correct }
        if offset == picked { return .wrong }
        return .dimmed
    }

    private func pick(_ offset: Int, answer: Int) {
        guard picked == nil else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            picked = offset
            results.append(offset == answer)
        }
        if offset != answer {
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
        }
    }

    // MARK: - Failure

    private func failure(_ message: String, fix: Fix) -> some View {
        let (emoji, title, label) = switch fix {
        case .addKey: ("🔑", "One quick setup", "Add API key")
        case .retry: ("😵‍💫", "That didn't work", "Try again")
        case .backToNote: ("📝", "Nothing to quiz yet", "Back to note")
        }

        let card = VStack(spacing: 16) {
            Text(emoji).font(.system(size: 72))
            Text(title)
                .font(.system(.title, design: .rounded, weight: .heavy))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(label) {
                switch fix {
                case .addKey: showSettings = true
                case .retry: Task { await load() }
                case .backToNote: dismiss()
                }
            }
            .font(.system(.headline, design: .rounded, weight: .bold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.pink)
            .controlSize(.large)
        }
        .padding(32)

        // Gemini's quota messages run several lines; scroll rather than clip the button in landscape.
        return ViewThatFits(in: .vertical) {
            card
            ScrollView { card }
        }
    }
}

// MARK: - Key lookup

enum GeminiKey {
    static var current: String? {
        if let key = KeychainHelper().getString(forKey: "gemini_api_key"), !key.isEmpty { return key }
        #if DEBUG
        // Lets a simulator run read the key from the launch environment instead of typing it into the UI.
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty { return key }
        #endif
        return nil
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

// MARK: - Pieces

private struct LoadingCard: View {
    @State private var bounce = false
    @State private var line = 0
    private let lines = ["Reading your notes…", "Sharpening pencils…", "Inventing sneaky wrong answers…", "Almost ready…"]

    var body: some View {
        VStack(spacing: 20) {
            Text("🧠")
                .font(.system(size: 96))
                .scaleEffect(bounce ? 1.12 : 0.92)
                .rotationEffect(.degrees(bounce ? 6 : -6))
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: bounce)
            Text(lines[line])
                .font(.system(.title3, design: .rounded, weight: .bold))
                .contentTransition(.opacity)
                .id(line)
                .transition(.opacity)
        }
        .onAppear { bounce = true }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation { line = (line + 1) % lines.count }
            }
        }
    }
}

private struct ProgressDots: View {
    let total: Int
    let results: [Bool]
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(color(i))
                    .frame(height: 8)
                    .frame(maxWidth: i == current ? 36 : .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, 48)
        .animation(.spring, value: results)
    }

    private func color(_ i: Int) -> Color {
        if i < results.count { return results[i] ? .green : .orange }
        return i == current ? .pink : .secondary.opacity(0.25)
    }
}

private struct OptionButton: View {
    enum State { case idle, correct, wrong, dimmed }
    static let tints: [Color] = [.blue, .purple, .orange, .teal]

    let letter: String
    let text: String
    let tint: Color
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(letter)
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .frame(width: 34, height: 34)
                    .background(badgeColor, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                Text(text)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if state == .correct { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3) }
                if state == .wrong { Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.title3) }
            }
            .padding(12)
            .background(Color(.systemBackground).opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(borderColor, lineWidth: state == .idle ? 1 : 3))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
            .scaleEffect(state == .correct ? 1.03 : 1)
            .opacity(state == .dimmed ? 0.45 : 1)
        }
        .buttonStyle(.plain)
    }

    private var badgeColor: Color {
        switch state {
        case .correct: .green
        case .wrong: .red
        default: tint
        }
    }

    private var borderColor: Color {
        switch state {
        case .correct: .green
        case .wrong: .red
        default: tint.opacity(0.3)
        }
    }
}

private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0))
    }
}

private struct ResultsCard: View {
    let quiz: Quiz
    let results: [Bool]
    let onRetry: () -> Void
    let onDone: () -> Void

    @State private var fill: Double = 0
    @State private var burst = false

    private var score: Int { results.filter { $0 }.count }
    private var fraction: Double { quiz.questions.isEmpty ? 0 : Double(score) / Double(quiz.questions.count) }

    private var headline: (emoji: String, text: String) {
        switch fraction {
        case 1: ("🏆", "100% Amazing!")
        case 0.8...: ("✨", "So close to perfect")
        case 0.5...: ("👏", "Nice work")
        default: ("📚", "Round two?")
        }
    }

    var body: some View {
        let summary = VStack(spacing: 24) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(AngularGradient(colors: [.pink, .orange, .yellow, .green, .pink], center: .center),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(headline.emoji).font(.system(size: 52))
                    Text("\(score)/\(quiz.questions.count)")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                }
            }
            .frame(width: 210, height: 210)
            .overlay { EmojiBurst(active: burst, emojis: fraction >= 0.8 ? ["🎉", "⭐️", "💖", "✨"] : ["💪", "📚", "✏️"]) }

            Text(headline.text)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
            Text(quiz.title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)

        // The ring and headline are taller than an iPhone in landscape: centre them when they fit,
        // scroll them when they don't, and keep the buttons pinned either way.
        ViewThatFits(in: .vertical) {
            summary.frame(maxHeight: .infinity)
            ScrollView { summary.padding(.vertical, 24) }
        }
        .safeAreaInset(edge: .bottom, spacing: 24) {
            VStack(spacing: 10) {
                Button(action: onRetry) {
                    Label("New quiz", systemImage: "arrow.clockwise")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.pink, in: Capsule())
                        .foregroundStyle(.white)
                }
                Button("Back to note", action: onDone)
                    .font(.system(.headline, design: .rounded))
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .sensoryFeedback(.success, trigger: burst)
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.8).delay(0.15)) { fill = fraction }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { burst = true }
        }
    }
}

private struct EmojiBurst: View {
    let active: Bool
    let emojis: [String]

    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { i in
                let angle = Double(i) / 14 * 2 * .pi
                Text(emojis[i % emojis.count])
                    .font(.system(size: 28))
                    .offset(x: active ? cos(angle) * 170 : 0, y: active ? sin(angle) * 170 : 0)
                    .scaleEffect(active ? 1 : 0.2)
                    .opacity(active ? 0 : 1)
                    .animation(.easeOut(duration: 1.2).delay(Double(i) * 0.02), value: active)
            }
        }
        .allowsHitTesting(false)
    }
}
