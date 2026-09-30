import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What Quolio took from one source in a notebook. Kept with the notebook, so adding a source
/// only reads that one, and a source is read again only after it changes.
public struct SourceDigest: Codable, Equatable, Sendable {
    public var noteID: UUID
    /// The source's `modifiedAt` when it was read.
    public var sourceModifiedAt: Date
    public var title: String
    public var summary: String
    public var keyPoints: [String]

    public init(noteID: UUID, sourceModifiedAt: Date, title: String, summary: String, keyPoints: [String]) {
        self.noteID = noteID
        self.sourceModifiedAt = sourceModifiedAt
        self.title = title
        self.summary = summary
        self.keyPoints = keyPoints
    }
}

/// The notebook's sources taken together. Points cite sources as `[n]`, numbered in the order
/// the digests were given.
public struct NotebookOverview: Equatable, Sendable {
    public var overview: String
    public var themes: [String]
    public var agreements: [String]
    public var differences: [String]

    public init(overview: String, themes: [String] = [], agreements: [String] = [], differences: [String] = []) {
        self.overview = overview
        self.themes = themes
        self.agreements = agreements
        self.differences = differences
    }
}

/// Lays out a notebook's summary note and builds what the model reads to write it.
public enum NotebookSummary {
    /// About 1,300 tokens for all the digests together, leaving room for the instructions and answer.
    static let wordBudget = 900

    /// The digests numbered `[1]`, `[2]`… Each gets an equal share of the budget, so one long
    /// source can't crowd out the rest.
    static func sourcesText(_ digests: [SourceDigest], wordBudget: Int = wordBudget) -> String {
        let share = max(20, wordBudget / max(1, digests.count))
        return digests.enumerated().map { index, digest in
            let body = ([digest.summary] + digest.keyPoints.map { "- \($0)" }).joined(separator: "\n")
            return "[\(index + 1)] \(digest.title)\n\(body.prefix(words: share))"
        }.joined(separator: "\n\n")
    }

    /// The cited source numbers that are in range and share a word with the point, and one of its
    /// figures if it gives any. The on-device model sometimes names a source that says nothing
    /// about it, or credits both sources with one's price or date.
    static func supported(_ numbers: [Int], text: String, digests: [SourceDigest]) -> [Int] {
        let words = Set(SearchText.terms(text)).subtracting(SearchText.stopWords)
        let figures = words.filter { $0.contains(where: \.isNumber) }
        return Set(numbers).filter { number in
            guard digests.indices.contains(number - 1) else { return false }
            let digest = digests[number - 1]
            let terms = Set(SearchText.terms(([digest.title, digest.summary] + digest.keyPoints).joined(separator: " ")))
            return !words.isDisjoint(with: terms) && (figures.isEmpty || !figures.isDisjoint(with: terms))
        }.sorted()
    }

    /// The overview without a closing lead-in to a list ("It covers the following topics:"), which
    /// the model sometimes writes; the notebook shows the overview on its own.
    static func droppingLeadIn(_ overview: String) -> String {
        let text = overview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasSuffix(":"), let end = text.dropLast().lastIndex(where: { ".!?".contains($0) }) else { return text }
        return String(text[...end])
    }

    /// Whether a difference only says a source leaves something out ("Source 1 does not mention
    /// this"). The model writes these, but one source covering more isn't the sources disagreeing.
    static func isOmission(_ difference: String) -> Bool {
        guard let pattern = try? Regex(#"\b(?:(?:does|do|did)\s+not|doesn't|don't|didn't)\s+(?:mention|discuss|cover|address|include)\b|\bno mention\b|\bnot mentioned\b|\bno specific\b|\bnot specified\b"#).ignoresCase()
        else { return false }
        return difference.contains(pattern)
    }

    /// Whether a claim gives a figure, in digits or words: the on-device model compares figures
    /// well, but judges claims about different things, worded differently, to disagree.
    static func hasFigure(_ text: String) -> Bool {
        text.contains(where: \.isNumber)
            || text.lowercased().split(whereSeparator: { !$0.isLetter }).contains { numberWords.contains(String($0)) }
    }

    private static let numberWords: Set<String> = [
        "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million", "billion",
    ]

    /// "Parking: $8 a day [1]; $10 from June [2]." — one thing the sources say differently.
    static func difference(_ subject: String, _ claims: [(says: String, sources: [Int])]) -> String {
        let said = claims.map { citing($0.says.trimmingCharacters(in: CharacterSet(charactersIn: ". ")), $0.sources) }
        return "\(subject.trimmingCharacters(in: CharacterSet(charactersIn: ": "))): \(said.joined(separator: "; "))."
    }

    /// "Costs rose [1, 3]." — the citation goes inside the sentence's full stop.
    static func citing(_ text: String, _ numbers: [Int]) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !numbers.isEmpty else { return text }
        let marker = "[\(numbers.map(String.init).joined(separator: ", "))]"
        return text.hasSuffix(".") ? "\(text.dropLast()) \(marker)." : "\(text) \(marker)"
    }

    /// The summary note: the overview, the themes, where the sources agree and differ, then what
    /// each source says, numbered to match the citations.
    public static func blocks(overview: NotebookOverview, digests: [SourceDigest]) -> [Block] {
        var blocks: [Block] = []
        func add(_ type: BlockType, _ text: String) {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(Block(type: type, runs: [.plain(text)])) }
        }
        func section(_ heading: String, _ items: [String]) {
            let items = items.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !items.isEmpty else { return }
            add(.heading(level: 2), heading)
            items.forEach { add(.bulletedList, $0) }
        }

        add(.paragraph, overview.overview)
        section("Key themes", overview.themes)
        // With one source there is nothing to compare.
        if digests.count > 1 {
            section("Where sources agree", overview.agreements)
            section("Where sources differ", overview.differences)
        }
        if !digests.isEmpty {
            add(.heading(level: 2), "Sources")
            for (index, digest) in digests.enumerated() {
                add(.heading(level: 3), "[\(index + 1)] \(digest.title)")
                add(.paragraph, digest.summary)
                digest.keyPoints.forEach { add(.bulletedList, $0) }
            }
        }
        return blocks
    }
}

#if canImport(FoundationModels)
/// Reads each source in a notebook, then writes an overview of them all, with Apple's on-device
/// model. Nothing leaves the device.
@available(iOS 26, macOS 26, *)
public struct OnDeviceNotebookSummarizer: Sendable {
    public init() {}

    /// What one source says. A long source is read in parts first, like a long recording.
    public func digest(title: String, text: String) async throws -> (summary: String, keyPoints: [String]) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OnDeviceAIError.emptyNotes }
        let (condensed, isNotes) = try await OnDeviceMeetingAnalyzer().condensed(
            text, instructions: Self.digestInstructions, as: PartNotes.self
        ) { index, count, isNotes in
            """
            This is part \(index + 1) of \(count) of \(isNotes ? "notes on " : "")a source titled "\(title)". \
            Note what this part says: its facts, claims and arguments.
            """
        }
        let session = LanguageModelSession(instructions: Self.digestInstructions)
        let prompt = """
            \(isNotes ? "These are notes on the parts of one source, in order." : "This is one source.") \
            Its title is "\(title)". Write its summary and key points.

            \(condensed)
            """
        let summary = try await session.respond(to: prompt, generating: Summary.self).content
        return (summary.summary, summary.keyPoints)
    }

    /// The sources taken together, citing them by their place in `digests`.
    public func overview(of digests: [SourceDigest]) async throws -> NotebookOverview {
        guard !digests.isEmpty else { throw OnDeviceAIError.emptyNotes }
        let session = LanguageModelSession(instructions: Self.overviewInstructions)
        let prompt = """
            These are summaries of the \(digests.count) sources in one notebook, numbered. Write an \
            overview of them together and the key themes.

            \(NotebookSummary.sourcesText(digests))
            """
        let result = try await session.respond(to: prompt, generating: Overview.self).content
        // The model is better at naming its sources in a field than at writing [n] inline.
        let themes = result.themes.map { point in
            NotebookSummary.citing(point.text, NotebookSummary.supported(point.sources, text: point.text, digests: digests))
        }
        let (agreements, differences) = digests.count > 1 ? try await compare(digests) : ([], [])
        return NotebookOverview(overview: NotebookSummary.droppingLeadIn(result.overview), themes: themes,
                                agreements: agreements, differences: differences)
    }

    /// Where the sources agree and differ. The model first lists the things two or more sources
    /// speak about and what each says; then, for each thing they put differently, the figures they
    /// give are judged on their own. Asked for agreements and differences directly, it misses a
    /// changed price and invents disagreements between sources that cover different topics.
    private func compare(_ digests: [SourceDigest]) async throws -> (agreements: [String], differences: [String]) {
        let session = LanguageModelSession(instructions: Self.overviewInstructions)
        let prompt = """
            These are summaries of the \(digests.count) sources in one notebook, numbered. List the \
            things that two or more of them speak about, and what each of those sources says.

            \(NotebookSummary.sourcesText(digests))
            """
        let subjects = try await session.respond(to: prompt, generating: Overlap.self).content.subjects
        var agreements: [String] = [], differences: [String] = []
        for subject in subjects {
            let found = subject.claims.filter { claim in
                !NotebookSummary.isOmission(claim.says)
                    && !NotebookSummary.supported([claim.source], text: claim.says, digests: digests).isEmpty
            }
            let claims = NotebookChat.claims(found.map { (source: $0.source, says: $0.says) }, count: digests.count)
            // Agreeing or differing takes two sources.
            guard Set(claims.flatMap(\.sources)).count > 1, let first = claims.first else { continue }
            // Said in the same words: the sources agree.
            guard claims.count > 1 else {
                let agreeing = NotebookSummary.supported(first.sources, text: first.says, digests: digests)
                if agreeing.count > 1 { agreements.append(NotebookSummary.citing(first.says, agreeing)) }
                continue
            }
            // Said differently: only figures are compared.
            let figures = claims.filter { NotebookSummary.hasFigure($0.says) }
            guard Set(figures.flatMap(\.sources)).count > 1, let figure = figures.first else { continue }
            let comparison = try await OnDeviceNotebookChat.compare(figures, question: "What do the sources say about \(subject.name)?")
            switch comparison {
            case .agree:
                // The agreement is shown in the first source's words: cite only the sources that bear them out.
                let agreeing = NotebookSummary.supported(Set(figures.flatMap(\.sources)).sorted(), text: figure.says, digests: digests)
                if agreeing.count > 1 { agreements.append(NotebookSummary.citing(figure.says, agreeing)) }
            case .conflict: differences.append(NotebookSummary.difference(subject.name, figures))
            case .unrelated: break
            }
        }
        return (agreements, differences)
    }

    private static let digestInstructions = """
        You summarize the user's sources: documents, web pages, notes and meeting transcripts. \
        Only state what the source says: never invent a name, number, fact or claim.
        """

    private static let overviewInstructions = """
        You write an overview of a notebook of the user's sources from a summary of each. The \
        sources are numbered; for each point, give the numbers of the sources it comes from. Only \
        state what the summaries say: never invent a fact or a source number. Sources that cover \
        different topics don't disagree: they differ only where they say different things about the \
        same thing.
        """

    @Generable
    struct PartNotes: OnDeviceMeetingAnalyzer.PartNoting {
        @Guide(description: "Two or three sentences on what this part says")
        var summary: String
        // Bounded: a dense page can otherwise list points until the answer overflows the context.
        @Guide(description: "The facts, claims and arguments in this part, in order", .maximumCount(12))
        var points: [String]

        var text: String {
            ([summary] + points.map { "Point: \($0)" }).joined(separator: "\n")
        }
    }

    @Generable
    struct Summary {
        @Guide(description: "Three to five sentences on what the source says")
        var summary: String
        @Guide(description: "Its main points, facts or arguments, most important first", .maximumCount(6))
        var keyPoints: [String]
    }

    @Generable
    struct Point {
        @Guide(description: "One sentence")
        var text: String
        @Guide(description: "The numbers of the sources this comes from")
        var sources: [Int]
    }

    @Generable
    struct Overview {
        @Guide(description: "Three to five sentences on what the sources cover together")
        var overview: String
        @Guide(description: "The main themes across the sources, each a sentence on what they say about it", .maximumCount(5))
        var themes: [Point]
    }

    @Generable
    struct Overlap {
        @Guide(description: "Each thing two or more sources speak about, such as a price, a date, a place or a rule", .maximumCount(5))
        var subjects: [Subject]
    }

    @Generable
    struct Subject {
        @Guide(description: "What it is, in a few words")
        var name: String
        @Guide(description: "What each source says about exactly this thing, leaving out a source that says nothing about it")
        var claims: [Claim]
    }

    @Generable
    struct Claim {
        @Guide(description: "The source's number")
        var source: Int
        @Guide(description: "What it says about this, in a few words, with any figure or date it gives")
        var says: String
    }
}
#endif
