import Foundation

/// The ruling printed behind a note's blocks.
public enum PaperStyle: String, CaseIterable, Sendable {
    case lined, grid, dotted, blank
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
    let outline: [Line]

    /// Fresh blocks on every call, so two notes made from one template never share block ids.
    /// Blank lines get no runs, so the editor shows its placeholder in them.
    public func makeBlocks() -> [Block] {
        outline.map { Block(type: $0.type, runs: $0.text.isEmpty ? [] : [.plain($0.text)]) }
    }

    public static let all: [NoteTemplate] = [
        NoteTemplate(id: "lined", name: "Lined paper", category: .paper, paper: .lined, outline: []),
        NoteTemplate(id: "grid", name: "Grid paper", category: .paper, paper: .grid, outline: []),
        NoteTemplate(id: "dotted", name: "Dot grid", category: .paper, paper: .dotted, outline: []),
        NoteTemplate(id: "blank", name: "Blank page", category: .paper, paper: .blank, outline: []),

        NoteTemplate(
            id: "weekly-planner", name: "Weekly planner", category: .planning, paper: .lined,
            outline: [.text("Week of: "), .heading("Top 3 this week"), .number(), .number(), .number()]
                + weekdays.flatMap { [.subheading($0), .todo()] }
                + [.heading("Notes"), .text()]
        ),
        NoteTemplate(
            id: "todo-list", name: "To-do list", category: .planning, paper: .lined,
            outline: [
                .heading("Must do"), .todo(), .todo(), .todo(),
                .heading("Should do"), .todo(), .todo(),
                .heading("Could do"), .todo(),
            ]
        ),
        NoteTemplate(
            id: "meal-planner", name: "Meal planner & grocery list", category: .planning, paper: .blank,
            outline: [.heading("Grocery list"), .todo(), .todo(), .todo(), .todo()]
                + weekdays.flatMap { [.subheading($0), .bullet("Breakfast: "), .bullet("Lunch: "), .bullet("Dinner: ")] }
        ),
        NoteTemplate(
            id: "daily-journal", name: "Daily journal", category: .planning, paper: .dotted,
            outline: [
                .text("Date: "), .quote("Mood: "),
                .heading("Grateful for"), .number(), .number(), .number(),
                .heading("Today's focus"), .todo(), .todo(),
                .heading("Reflection"), .text(),
            ]
        ),
        NoteTemplate(
            id: "lecture-notes", name: "Lecture notes", category: .study, paper: .grid,
            outline: [
                .text("Subject: "), .text("Date: "), .callout("💡", "Key idea: "),
                .heading("Notes"), .bullet(),
                .heading("Questions"), .bullet(),
                .heading("Summary"), .text(),
            ]
        ),
        NoteTemplate(
            id: "meeting-notes", name: "Meeting notes", category: .work, paper: .lined,
            outline: [
                .text("Date: "), .text("Attendees: "),
                .heading("Agenda"), .number(),
                .heading("Notes"), .bullet(),
                .heading("Decisions"), .bullet(),
                .heading("Action items"), .todo(),
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
