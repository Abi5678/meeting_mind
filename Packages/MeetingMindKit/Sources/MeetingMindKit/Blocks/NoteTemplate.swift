import Foundation

/// The ruling printed behind a note's blocks.
public enum PaperStyle: String, CaseIterable, Sendable {
    case lined, grid, dotted, blank
}

/// The paper colour behind the ruling. Held as sRGB components because this package is
/// Foundation-only; the app turns them into a `Color`.
public enum PaperTint: String, CaseIterable, Sendable {
    case cream, white, sepia, mint, sky, blush, lavender, graphite

    public var displayName: String { rawValue.capitalized }

    /// Light-mode sRGB components, 0–1.
    public var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .cream: (0.99, 0.97, 0.91)
        case .white: (1.00, 1.00, 1.00)
        case .sepia: (0.96, 0.91, 0.82)
        case .mint: (0.90, 0.96, 0.92)
        case .sky: (0.90, 0.94, 0.99)
        case .blush: (0.99, 0.92, 0.93)
        case .lavender: (0.94, 0.92, 0.99)
        case .graphite: (0.89, 0.90, 0.92)
        }
    }

    /// Dark-mode components. Kept dark enough that `InkColor` text stays legible on top.
    public var darkComponents: (red: Double, green: Double, blue: Double) {
        switch self {
        case .cream: (0.16, 0.15, 0.13)
        case .white: (0.13, 0.13, 0.14)
        case .sepia: (0.19, 0.16, 0.12)
        case .mint: (0.11, 0.17, 0.14)
        case .sky: (0.11, 0.14, 0.20)
        case .blush: (0.20, 0.13, 0.14)
        case .lavender: (0.16, 0.13, 0.21)
        case .graphite: (0.15, 0.16, 0.17)
        }
    }
}

/// A starting point for a new note: a paper style plus pre-filled blocks.
public struct NoteTemplate: Identifiable, Sendable {
    public enum Category: String, CaseIterable, Sendable {
        case paper = "Paper"
        case planning = "Planning"
        case study = "Study"
        case work = "Work"
    }

    struct Line: Sendable {
        let type: BlockType
        let text: String
    }

    public let id: String
    public let name: String
    public let category: Category
    public let paper: PaperStyle
    /// The page colour a new note starts on; the gallery previews it and the editor can change it.
    public let tint: PaperTint
    let outline: [Line]

    init(id: String, name: String, category: Category, paper: PaperStyle,
         tint: PaperTint = .cream, outline: [Line]) {
        self.id = id
        self.name = name
        self.category = category
        self.paper = paper
        self.tint = tint
        self.outline = outline
    }

    /// Fresh blocks on every call, so two notes made from one template never share block ids.
    /// Blank lines get no runs, so the editor shows its placeholder in them.
    public func makeBlocks() -> [Block] {
        outline.map { Block(type: $0.type, runs: $0.text.isEmpty ? [] : [.plain($0.text)]) }
    }

    public static let all: [NoteTemplate] = [
        NoteTemplate(id: "lined", name: "Lined paper", category: .paper, paper: .lined, tint: .cream, outline: []),
        NoteTemplate(id: "grid", name: "Grid paper", category: .paper, paper: .grid, tint: .white, outline: []),
        NoteTemplate(id: "dotted", name: "Dot grid", category: .paper, paper: .dotted, tint: .sepia, outline: []),
        NoteTemplate(id: "blank", name: "Blank page", category: .paper, paper: .blank, tint: .white, outline: []),

        NoteTemplate(
            id: "weekly-planner", name: "Weekly planner", category: .planning, paper: .lined, tint: .sky,
            outline: [.text("Week of: "), .heading("Top 3 this week"), .number(), .number(), .number()]
                + weekdays.flatMap { [.subheading($0), .todo()] }
                + [.heading("Notes"), .text()]
        ),
        NoteTemplate(
            id: "todo-list", name: "To-do list", category: .planning, paper: .lined, tint: .mint,
            outline: [
                .heading("Must do"), .todo(), .todo(), .todo(),
                .heading("Should do"), .todo(), .todo(),
                .heading("Could do"), .todo(),
            ]
        ),
        NoteTemplate(
            id: "meal-planner", name: "Meal planner & grocery list", category: .planning, paper: .blank, tint: .blush,
            outline: [.heading("Grocery list"), .todo(), .todo(), .todo(), .todo()]
                + weekdays.flatMap { [.subheading($0), .bullet("Breakfast: "), .bullet("Lunch: "), .bullet("Dinner: ")] }
        ),
        NoteTemplate(
            id: "daily-journal", name: "Daily journal", category: .planning, paper: .dotted, tint: .lavender,
            outline: [
                .text("Date: "), .quote("Mood: "),
                .heading("Grateful for"), .number(), .number(), .number(),
                .heading("Today's focus"), .todo(), .todo(),
                .heading("Reflection"), .text(),
            ]
        ),
        NoteTemplate(
            id: "habit-tracker", name: "Habit tracker", category: .planning, paper: .grid, tint: .mint,
            outline: [.text("Month: "), .callout("🔥", "Streak to beat: ")]
                + ["Move", "Read", "Sleep by 11", "No screens after 10"]
                    .flatMap { [.subheading($0) as Line] + weekdays.map { .todo($0) } }
        ),

        NoteTemplate(
            id: "cornell-notes", name: "Cornell notes", category: .study, paper: .lined, tint: .sky,
            outline: [
                .text("Course: "), .text("Date: "),
                .heading("Cue questions"), .number(), .number(), .number(),
                .heading("Notes"), .bullet(), .bullet(), .bullet(),
                .callout("✅", "Summary in your own words: "),
            ]
        ),
        NoteTemplate(
            id: "lecture-notes", name: "Lecture notes", category: .study, paper: .grid, tint: .cream,
            outline: [
                .text("Subject: "), .text("Date: "), .callout("💡", "Key idea: "),
                .heading("Notes"), .bullet(),
                .heading("Questions"), .bullet(),
                .heading("Summary"), .text(),
            ]
        ),
        NoteTemplate(
            id: "reading-log", name: "Reading log", category: .study, paper: .dotted, tint: .sepia,
            outline: [
                .text("Title: "), .text("Author: "), .quote("Best line so far: "),
                .heading("Key takeaways"), .number(), .number(), .number(),
                .heading("Questions it raised"), .bullet(),
                .callout("⭐️", "Rating: "),
            ]
        ),

        NoteTemplate(
            id: "meeting-notes", name: "Meeting notes", category: .work, paper: .lined, tint: .cream,
            outline: [
                .text("Date: "), .text("Attendees: "),
                .heading("Agenda"), .number(),
                .heading("Notes"), .bullet(),
                .heading("Decisions"), .bullet(),
                .heading("Action items"), .todo(),
            ]
        ),
        NoteTemplate(
            id: "project-brief", name: "Project brief", category: .work, paper: .blank, tint: .graphite,
            outline: [
                .heading("Problem"), .text(),
                .heading("Goal"), .callout("🎯", "Success looks like: "),
                .heading("Scope"), .bullet("In: "), .bullet("Out: "),
                .heading("Milestones"), .number(), .number(),
                .heading("Risks"), .bullet(),
            ]
        ),
        NoteTemplate(
            id: "one-on-one", name: "1:1 agenda", category: .work, paper: .lined, tint: .lavender,
            outline: [
                .text("With: "), .text("Date: "),
                .heading("Wins since last time"), .bullet(),
                .heading("What's blocking me"), .bullet(),
                .heading("Feedback both ways"), .text(),
                .heading("Action items"), .todo(), .todo(),
            ]
        ),
        NoteTemplate(
            id: "retro", name: "Retrospective", category: .work, paper: .grid, tint: .blush,
            outline: [
                .text("Sprint / period: "),
                .heading("😀 Went well"), .bullet(), .bullet(),
                .heading("😕 Didn't go well"), .bullet(), .bullet(),
                .heading("💡 Try next time"), .todo(), .todo(),
            ]
        ),
    ]

    private static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
}

extension NoteTemplate.Line {
    static func heading(_ text: String) -> Self { Self(type: .heading(level: 2), text: text) }
    static func subheading(_ text: String) -> Self { Self(type: .heading(level: 3), text: text) }
    static func text(_ text: String = "") -> Self { Self(type: .paragraph, text: text) }
    static func bullet(_ text: String = "") -> Self { Self(type: .bulletedList, text: text) }
    static func number(_ text: String = "") -> Self { Self(type: .numberedList, text: text) }
    static func todo(_ text: String = "") -> Self { Self(type: .todo, text: text) }
    static func quote(_ text: String) -> Self { Self(type: .quote, text: text) }
    static func callout(_ emoji: String, _ text: String) -> Self { Self(type: .callout(emoji: emoji), text: text) }
}
