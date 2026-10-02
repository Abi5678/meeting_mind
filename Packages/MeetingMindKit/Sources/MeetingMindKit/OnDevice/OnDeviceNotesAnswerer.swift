#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Answers a question from the user's notes with Apple's on-device model, so neither the question
/// nor the notes leave the device.
@available(iOS 26, macOS 26, *)
public struct OnDeviceNotesAnswerer: Sendable {
    public init() {}

    public static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public func answer(question: String, sources: [NotesQuestion.Source]) async throws -> String {
        let session = LanguageModelSession(instructions: NotesQuestion.instructions)
        let prompt = NotesQuestion.prompt(question: question, sources: sources)
        // Greedy: the likeliest words, not sampled ones, which wander from the sources.
        let answer = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy)).content
        return NotesQuestion.withoutUnsupportedNumbers(answer.trimmingCharacters(in: .whitespacesAndNewlines), in: [prompt])
    }
}
#endif
