import Testing

@testable import MeetingMindKit

#if canImport(NaturalLanguage)
@Suite("Key points")
struct KeyPointsTests {
    static let meeting = """
    Speaker 1: Okay, so let's get started. Thanks everyone for joining.
    Speaker 1: The main thing today is the launch date for the mobile app and whether the budget still works.
    Speaker 2: Right. So on the launch, engineering thinks we can ship the mobile app on March fifteenth if the payment bug is fixed this week.
    Speaker 2: The payment bug only shows up on older Android phones, but it blocks checkout completely.
    Speaker 3: How many users does that affect?
    Speaker 2: About eight percent of our checkout traffic comes from those phones.
    Speaker 1: That's too many to ship with. Let's make the payment bug the top priority for the team.
    Speaker 3: Agreed. I can move two engineers from the dashboard work onto the payment bug.
    Speaker 1: Great. Now the budget. Marketing asked for another forty thousand dollars for the launch campaign.
    Speaker 3: The current budget only has twenty five thousand left for the quarter.
    Speaker 2: Could we split the campaign, run a smaller launch campaign in March and the rest in April when the new budget opens?
    Speaker 1: I like that. Splitting the campaign keeps us inside the budget and still gets the launch noticed.
    Speaker 3: I'll talk to marketing about a split campaign and come back with numbers by Friday.
    Speaker 1: Okay. Anything else? Yeah.
    Speaker 2: Just that the app store review can take a week, so we should submit the mobile app by March eighth.
    Speaker 1: Good point. So the plan is fix the payment bug, submit the app by March eighth, launch on March fifteenth.
    Speaker 3: Sounds good. Um, I think that's it.
    Speaker 1: Thanks all.
    """

    @Test("Picks whole sentences that cover different topics, in the order they were said")
    func picksCoveringSentences() throws {
        let points = KeyPoints.sentences(in: Self.meeting)
        #expect(points.count == 3)
        let positions = try points.map { try #require(Self.meeting.range(of: $0)?.lowerBound) }
        #expect(positions == positions.sorted())
        #expect(points.contains { $0.contains("payment bug") })
        #expect(points.contains { $0.contains("campaign") })
        #expect(points.allSatisfy { !$0.hasPrefix("Speaker") })
    }

    @Test("A long recording gets more points, up to eight")
    func longRecording() {
        let long = (1...20).map { "Topic \($0): " + Self.meeting.replacingOccurrences(of: "budget", with: "budget\($0)") }.joined(separator: "\n")
        #expect(KeyPoints.sentences(in: long).count == 8)
    }

    @Test("Nothing worth picking gives no analysis rather than an empty one")
    func nothingToPick() {
        #expect(KeyPoints.analysis(of: "") == nil)
        #expect(KeyPoints.analysis(of: "Hi. Okay. Yes.") == nil)
        let analysis = KeyPoints.analysis(of: Self.meeting)
        #expect(analysis?.summary == "")
        #expect(analysis?.keyPoints.count == 3)
    }
}
#endif
