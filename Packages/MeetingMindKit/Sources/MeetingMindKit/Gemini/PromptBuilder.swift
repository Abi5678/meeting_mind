import Foundation

public enum PromptBuilder {
    /// What the model must use as `owner` when the transcript names nobody. Mirrored in
    /// `GeminiSchema.meetingAnalysis` so the constrained decode agrees with the prose.
    public static let unassignedOwner = "Unassigned"

    /// Builds the single-shot analysis prompt. Every instruction here exists to keep the
    /// output grounded: a 90-minute transcript gives the model plenty of room to confabulate
    /// owners and deadlines that were never spoken.
    public static func analysisPrompt(transcript: String) -> String {
        """
        You are analysing the transcript of one meeting. The transcript comes from automatic \
        speech recognition, so expect misheard words, missing punctuation, and no reliable \
        speaker labels.

        Produce a summary, the key decisions, the action items, and a follow-up email.

        Rules:
        - Ground every statement in the transcript. Never introduce a fact, name, number, or \
        deadline that was not spoken.
        - keyDecisions: only choices the participants actually settled on. If the meeting \
        settled nothing, return an empty list rather than inventing a decision.
        - actionItems: only concrete work someone committed to. Set `owner` to the name as \
        spoken. If the transcript does not say who owns it, set `owner` to "\(unassignedOwner)".
        - actionItems: set `due` only when a deadline was actually stated, copying it as spoken \
        ("Friday", "end of Q3"). Omit `due` entirely when no deadline was given.
        - followUpEmail: a recap the organiser could send as-is, covering the decisions and the \
        action items with their owners.
        - If the transcript is too short or too garbled to analyse, say so plainly in `summary` \
        and return empty lists.

        TRANSCRIPT:
        \(transcript)
        """
    }

    /// Builds the quiz prompt. The quiz tests recall of the user's own notes, so every question
    /// and correct answer must come from the notes, never from the model's general knowledge.
    public static func quizPrompt(notes: String, questionCount: Int) -> String {
        """
        You are writing a multiple-choice quiz that helps someone check what they remember \
        from their own notes.

        Write \(questionCount) questions. If the notes are too short to support \(questionCount) \
        distinct questions, write fewer rather than repeating yourself or going beyond the notes.

        Rules:
        - Every question and every correct answer must come from the notes. Never test \
        outside knowledge.
        - Each question has exactly 4 options: one correct, three plausible but clearly wrong \
        given the notes. Keep options short.
        - answerIndex is the zero-based position of the correct option. Vary it across questions.
        - explanation: one short sentence saying why the correct option is right. It is shown \
        whether the learner answered right or wrong, so never open with praise like "That's right!".
        - title: a short, playful title for the quiz, based on the notes' topic.

        NOTES:
        \(notes)
        """
    }
}
