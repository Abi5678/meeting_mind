import Foundation
import Testing

@testable import MeetingMindKit

@Suite("NoteTemplate")
struct NoteTemplateTests {
    static func template(_ id: String) throws -> NoteTemplate {
        try #require(NoteTemplate.all.first { $0.id == id })
    }

    @Test("Template ids are unique")
    func uniqueIDs() {
        let ids = NoteTemplate.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Paper templates start empty and every other template has content")
    func paperTemplatesAreEmpty() {
        for template in NoteTemplate.all {
            #expect(template.makeBlocks().isEmpty == (template.category == .paper), "\(template.id)")
        }
    }

    @Test("Every paper style has its own starter page")
    func everyPaperStyleOffered() {
        let styles = NoteTemplate.all.filter { $0.category == .paper }.map(\.paper)
        #expect(Set(styles) == Set(PaperStyle.allCases))
        #expect(styles.count == PaperStyle.allCases.count)
    }

    @Test("Each use of a template gets fresh block ids")
    func freshIDs() throws {
        let template = try Self.template("weekly-planner")
        let first = template.makeBlocks()
        let second = template.makeBlocks()

        #expect(first.map(\.plainText) == second.map(\.plainText))
        #expect(Set(first.map(\.id)).isDisjoint(with: second.map(\.id)))
    }

    @Test("Blank lines have no runs so the editor shows its placeholder")
    func blankLinesHaveNoRuns() throws {
        let blocks = try Self.template("todo-list").makeBlocks()
        let todos = blocks.filter { $0.type == .todo }

        #expect(todos.count == 6)
        #expect(todos.allSatisfy { $0.runs.isEmpty })
        #expect(blocks.first == Block(id: blocks[0].id, type: .heading(level: 2), runs: [.plain("Must do")]))
    }

    @Test("The weekly planner has a heading and a to-do for every day")
    func weeklyPlannerDays() throws {
        let blocks = try Self.template("weekly-planner").makeBlocks()
        let days = blocks.filter { $0.type == .heading(level: 3) }.map(\.plainText)

        #expect(days == ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"])
        for day in days {
            let index = try #require(blocks.firstIndex { $0.plainText == day })
            #expect(blocks[index + 1].type == .todo)
        }
    }
}
