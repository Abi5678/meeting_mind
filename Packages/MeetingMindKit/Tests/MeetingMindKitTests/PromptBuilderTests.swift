import Testing

@testable import MeetingMindKit

@Suite("PromptBuilder")
struct PromptBuilderTests {
    @Test("The transcript is embedded verbatim")
    func embedsTranscript() {
        let transcript = "Sam: I'd cut Notion sync entirely for v1."
        #expect(PromptBuilder.analysisPrompt(transcript: transcript).contains(transcript))
    }

    @Test("The transcript is last, so a long one cannot bury the instructions")
    func transcriptComesLast() throws {
        let prompt = PromptBuilder.analysisPrompt(transcript: "Everything was decided.")
        let marker = try #require(prompt.range(of: "TRANSCRIPT:"))
        #expect(prompt[marker.upperBound...].contains("Everything was decided."))
    }

    @Test("Ownerless action items are told to use the Unassigned sentinel")
    func namesUnassignedSentinel() {
        let prompt = PromptBuilder.analysisPrompt(transcript: "...")
        #expect(prompt.contains(#""\#(PromptBuilder.unassignedOwner)""#))
        #expect(PromptBuilder.unassignedOwner == "Unassigned")
    }

    @Test("The prompt forbids inventing facts and empty-lists rather than confabulating")
    func groundsEveryClaim() {
        let prompt = PromptBuilder.analysisPrompt(transcript: "...")
        #expect(prompt.contains("Ground every statement in the transcript"))
        #expect(prompt.contains("Never introduce a fact"))
        #expect(prompt.contains("empty list rather than inventing a decision"))
    }

    @Test("The prompt warns that the transcript comes from ASR")
    func warnsAboutASR() {
        let prompt = PromptBuilder.analysisPrompt(transcript: "...")
        #expect(prompt.contains("automatic speech recognition"))
    }

    @Test("A deadline is only recorded when one was spoken")
    func dueOnlyWhenStated() {
        let prompt = PromptBuilder.analysisPrompt(transcript: "...")
        #expect(prompt.contains("only when a deadline was actually stated"))
        #expect(prompt.contains("Omit `due` entirely"))
    }
}
