//
//  FlashcardsView.swift
//  Instant Notes
//
// Flashcards: Apple's on-device model turns the open note into question-and-answer cards. Tap to
// flip; "Again" sends a card to the back of the pile, "Got it" puts it away.

import SwiftUI
import MeetingMindKit

struct FlashcardsView: View {
    let noteTitle: String
    let notesText: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .loading
    @State private var pile: [FlashcardDeck.Card] = []
    @State private var flipped = false
    @State private var turn = 0
    @State private var missed: Set<FlashcardDeck.Card> = []

    enum Phase {
        case loading
        case failed(message: String, fix: QuizView.Fix)
        case studying(FlashcardDeck)
        case finished(FlashcardDeck)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.16), .teal.opacity(0.10), .blue.opacity(0.14)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            switch phase {
            case .loading:
                LoadingCard(emoji: "🗂️", lines: ["Reading your notes…", "Picking out the key facts…", "Writing the cards…", "Almost ready…"])
            case let .failed(message, fix): failure(message, fix: fix)
            case let .studying(deck): studying(deck)
            case let .finished(deck): finished(deck)
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
            .accessibilityLabel("Close flashcards")
        }
        .task { await load() }
    }

    // MARK: - Loading

    private func load() async {
        phase = .loading
        guard AppleIntelligence.unavailableReason == nil, #available(iOS 26, *) else {
            phase = .failed(message: AppleIntelligence.unavailableReason ?? "", fix: .unavailable)
            return
        }
        let blank = notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        do {
            let deck = try await OnDeviceFlashcardWriter().deck(fromNotes: blank ? "" : "\(noteTitle)\n\n\(notesText)")
            start(deck)
        } catch OnDeviceAIError.notEnoughContent {
            phase = .failed(message: "There isn't enough in this note to make flashcards yet. Add a few more lines.", fix: .backToNote)
        } catch {
            phase = .failed(message: error.localizedDescription, fix: error as? OnDeviceAIError == .emptyNotes ? .backToNote : .retry)
        }
    }

    private func start(_ deck: FlashcardDeck) {
        pile = deck.cards
        flipped = false
        missed = []
        turn += 1
        withAnimation(.spring) { phase = .studying(deck) }
    }

    // MARK: - Studying

    private func studying(_ deck: FlashcardDeck) -> some View {
        let learned = deck.cards.count - pile.count

        return VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(deck.title.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1.5)
                    .foregroundStyle(.indigo)
                ProgressView(value: Double(learned), total: Double(deck.cards.count))
                    .tint(.green)
                Text("\(learned) of \(deck.cards.count) learned")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.top, 56)

            if let card = pile.first {
                FlipCard(card: card, flipped: flipped, reduceMotion: reduceMotion)
                    .id(turn)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                     removal: .move(edge: .leading).combined(with: .opacity)))
                    .onTapGesture { flip() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(flipped ? "Shows the question" : "Shows the answer")
            }
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 18) {
            Group {
                if flipped {
                    HStack(spacing: 12) {
                        pileButton("Again", systemImage: "arrow.uturn.backward", tint: .orange) { next(gotIt: false, deck) }
                        pileButton("Got it", systemImage: "checkmark", tint: .green) { next(gotIt: true, deck) }
                    }
                } else {
                    Text("Tap the card to see the answer")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .sensoryFeedback(.increase, trigger: learned)
    }

    private func pileButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(tint, in: Capsule())
                .foregroundStyle(.white)
        }
    }

    private func flip() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.75)) {
            flipped.toggle()
        }
    }

    private func next(gotIt: Bool, _ deck: FlashcardDeck) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            let card = pile.removeFirst()
            if !gotIt {
                pile.append(card)
                missed.insert(card)
            }
            flipped = false
            turn += 1
            if pile.isEmpty { phase = .finished(deck) }
        }
    }

    // MARK: - Finished

    private func finished(_ deck: FlashcardDeck) -> some View {
        let summary = VStack(spacing: 16) {
            Text(missed.isEmpty ? "🏆" : "🎉").font(.system(size: 96))
            Text("All \(deck.cards.count) cards learned")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
            Text(missed.isEmpty ? "Every one right the first time." : "\(missed.count) \(missed.count == 1 ? "card needed" : "cards needed") another go.")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)

        return ViewThatFits(in: .vertical) {
            summary.frame(maxHeight: .infinity)
            ScrollView { summary.padding(.vertical, 24) }
        }
        .safeAreaInset(edge: .bottom, spacing: 24) {
            VStack(spacing: 10) {
                pileButton("Study again", systemImage: "arrow.clockwise", tint: .indigo) { start(deck) }
                Button("Back to note") { dismiss() }
                    .font(.system(.headline, design: .rounded))
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Failure

    private func failure(_ message: String, fix: QuizView.Fix) -> some View {
        let (emoji, title, label) = switch fix {
        case .unavailable: ("✨", "Needs Apple Intelligence", "Back to note")
        case .retry: ("😵‍💫", "That didn't work", "Try again")
        case .backToNote: ("📝", "Nothing to study yet", "Back to note")
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
                case .retry: Task { await load() }
                case .unavailable, .backToNote: dismiss()
                }
            }
            .font(.system(.headline, design: .rounded, weight: .bold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.indigo)
            .controlSize(.large)
        }
        .padding(32)

        return ViewThatFits(in: .vertical) {
            card
            ScrollView { card }
        }
    }
}

// MARK: - Card

/// One card, turned over in 3D. With Reduce Motion the faces cross-fade instead.
private struct FlipCard: View {
    let card: FlashcardDeck.Card
    let flipped: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            face(card.front, label: "QUESTION", tint: .indigo)
                .opacity(flipped ? 0 : 1)
            face(card.back, label: "ANSWER", tint: .teal)
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (0, 1, 0))
        }
        .rotation3DEffect(.degrees(flipped && !reduceMotion ? 180 : 0), axis: (0, 1, 0), perspective: 0.6)
        .frame(maxWidth: 520, maxHeight: 420)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(flipped ? "Answer: \(card.back)" : "Question: \(card.front)")
    }

    private func face(_ text: String, label: String, tint: Color) -> some View {
        VStack(spacing: 14) {
            Text(label)
                .font(.caption.weight(.heavy))
                .tracking(1.5)
                .foregroundStyle(tint)
            ScrollView {
                Text(text)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).opacity(0.92), in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(tint.opacity(0.35), lineWidth: 2))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
}
