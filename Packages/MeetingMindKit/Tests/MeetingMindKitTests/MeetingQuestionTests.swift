import Foundation
import Testing

@testable import MeetingMindKit

@Suite("Meeting questions")
struct MeetingQuestionTests {
    @Test("The prompt has the excerpts, the conversation so far and the question")
    func prompt() {
        let prompt = MeetingChat.prompt(
            question: "When is it due?",
            excerpts: ["Launch prep", "Priya will own the launch plan, due Friday."],
            history: [
                MeetingChatTurn(role: .user, text: "Who owns the launch?"),
                MeetingChatTurn(role: .assistant, text: "Priya."),
            ]
        )
        #expect(prompt.contains("EXCERPTS FROM THE MEETING:\nLaunch prep\n\nPriya will own the launch plan, due Friday."))
        #expect(prompt.contains("User: Who owns the launch?\nYou: Priya."))
        #expect(prompt.hasSuffix("QUESTION: When is it due?"))
    }

    @Test("A first question says there is no conversation yet")
    func firstQuestion() {
        #expect(MeetingChat.prompt(question: "Q", excerpts: ["T"], history: []).contains("CONVERSATION SO FAR:\n(none)"))
    }

    @Test("Only the last few turns go along")
    func historyCap() {
        let history = (1...10).map { MeetingChatTurn(role: .user, text: "turn\($0)") }
        let prompt = MeetingChat.prompt(question: "Q", excerpts: [], history: history)
        #expect(!prompt.contains("turn6\n") && prompt.contains("turn7") && prompt.contains("turn10"))
    }

    @Test("A short meeting goes whole, and a transcript already in the notes isn't sent twice")
    func wholeMeeting() {
        let transcript = "Priya will own the launch plan."
        #expect(MeetingChat.excerpts(question: "Who?", transcript: transcript, notes: "Launch prep.", history: [])
            == ["Launch prep.", transcript])
        #expect(MeetingChat.excerpts(question: "Who?", transcript: transcript, notes: "Summary.\n\n\(transcript)", history: [])
            .joined().components(separatedBy: "Priya").count == 2)
    }

    @Test("A long meeting sends the parts that answer the question, in order, within the budget")
    func longMeeting() {
        let filler = (1...40).map { "We talked about item number \($0) for a while and moved on." }.joined(separator: " ")
        let transcript = filler + " Priya will write the press release by Friday. " + filler
        let excerpts = MeetingChat.excerpts(question: "Who writes the press release?", transcript: transcript,
                                            notes: "", history: [], wordBudget: 300)
        #expect(excerpts.joined(separator: " ").contains("press release by Friday"))
        #expect(excerpts.joined(separator: " ").split(whereSeparator: \.isWhitespace).count <= 300)
        // Topped up from the start once the matches are in.
        #expect(excerpts.first?.hasPrefix("We talked about item number 1 ") == true)
    }

    @Test("A follow-up finds its answer through the question before it")
    func followUp() {
        let filler = (1...40).map { "We talked about item number \($0) for a while and moved on." }.joined(separator: " ")
        let transcript = filler + " Priya will write the press release by Friday. " + filler
        let excerpts = MeetingChat.excerpts(
            question: "When is that due?", transcript: transcript, notes: "",
            history: [MeetingChatTurn(role: .user, text: "Who writes the press release?")], wordBudget: 150)
        #expect(excerpts.joined(separator: " ").contains("press release by Friday"))
    }
}
