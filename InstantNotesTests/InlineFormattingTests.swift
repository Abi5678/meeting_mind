//
//  InlineFormattingTests.swift
//  Instant Notes
//
// Bold, italic, code and links brought in from Notion must show in the editor, and must survive
// being typed into, split with Return and merged with Backspace.

import Foundation
import UIKit
import Testing
import MeetingMindKit
@testable import InstantNotes

@MainActor
@Suite("Inline formatting")
struct InlineFormattingTests {
    /// "Trail: **Mount Tam** loop". Offset 12 falls between "Mount" and " Tam".
    let trail: [InlineRun] = [.plain("Trail: "), InlineRun(text: "Mount Tam", isBold: true), .plain(" loop")]
    let head: [InlineRun] = [.plain("Trail: "), InlineRun(text: "Mount", isBold: true)]
    let tail: [InlineRun] = [InlineRun(text: " Tam", isBold: true), .plain(" loop")]
    let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 17)]

    @Test("Runs come back unchanged from the text view's attributes")
    func roundTrip() {
        let runs = trail + [
            InlineRun(text: "extra water", isItalic: true),
            .plain(", "),
            InlineRun(text: "brew", isCode: true),
            InlineRun(text: "the trail map", linkURL: URL(string: "https://example.com/map")),
        ]
        #expect(InlineText.runs(in: InlineText.attributedString(runs, attributes: body)) == runs)
    }

    @Test("Bold, italic and code get their own faces, and a link keeps its URL")
    func rendering() throws {
        let url = try #require(URL(string: "https://example.com"))
        let text = InlineText.attributedString([
            InlineRun(text: "b", isBold: true),
            InlineRun(text: "i", isItalic: true),
            InlineRun(text: "c", isCode: true),
            InlineRun(text: "l", linkURL: url),
        ], attributes: body)
        let traits = try (0..<4).map { index in
            try #require(text.attribute(.font, at: index, effectiveRange: nil) as? UIFont).fontDescriptor.symbolicTraits
        }
        #expect(traits[0].contains(.traitBold))
        #expect(traits[1].contains(.traitItalic))
        #expect(traits[2].contains(.traitMonoSpace))
        #expect(!traits[3].contains(.traitBold))
        #expect(text.attribute(.link, at: 3, effectiveRange: nil) as? URL == url)
    }

    @Test("A heading's bold face doesn't mark its plain words bold")
    func headingIsNotBoldRuns() {
        let heading: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 28, weight: .bold)]
        let runs: [InlineRun] = [.plain("Day one")]
        #expect(InlineText.runs(in: InlineText.attributedString(runs, attributes: heading)) == runs)
    }

    @Test("Typing inside a bold word stays bold")
    func typingInsideBold() {
        let (view, coordinator) = textView()
        view.selectedRange = NSRange(location: 12, length: 0)
        // Taking focus shows the placeholder, which restyles the text under the caret.
        view.configure(font: .systemFont(ofSize: 17), color: .label, lineHeight: 28, placeholder: "Type '/' for commands")
        view.insertText("ain")
        #expect(view.runs == [.plain("Trail: "), InlineRun(text: "Mountain Tam", isBold: true), .plain(" loop")])
        withExtendedLifetime(coordinator) {}
    }

    @Test("Typing inside a link stays in it, and typing straight after it doesn't join it")
    func typingAroundLink() {
        let url = URL(string: "https://example.com/map")
        let (view, coordinator) = textView([.plain("See "), InlineRun(text: "map", linkURL: url)])
        view.selectedRange = NSRange(location: 5, length: 0)
        view.insertText("a")
        view.selectedRange = NSRange(location: 8, length: 0)
        view.insertText(" now")
        #expect(view.runs == [.plain("See "), InlineRun(text: "maap", linkURL: url), .plain(" now")])
        withExtendedLifetime(coordinator) {}
    }

    @Test("Return in the middle of a bold word keeps both halves bold")
    func returnInsideBold() {
        var split: (lines: [[InlineRun]], caret: Int)?
        let (view, coordinator) = textView(onSplit: { split = ($0, $1) })
        defer { BlockUITextView.handoffAt = .distantPast }
        view.selectedRange = NSRange(location: 12, length: 0)

        let accepted = coordinator.textView(view, shouldChangeTextIn: NSRange(location: 12, length: 0), replacementText: "\n")
        #expect(!accepted)
        #expect(split?.lines == [head, tail])
        #expect(split?.caret == 0)
    }

    @Test("Editing a block keeps its runs")
    func updateTextKeepsRuns() {
        let block = Block(type: .paragraph, runs: trail)
        let state = editor(block)
        let edited: [InlineRun] = [.plain("Trail: "), InlineRun(text: "Mountain Tam", isBold: true), .plain(" loop")]
        state.updateText(block.id, edited)
        #expect(state.document[block.id]?.runs == edited)
        #expect(NoteMarkdownExporter.markdown(title: "Trail Notes", document: state.document).contains("Trail: **Mountain Tam** loop"))
    }

    @Test("Return keeps the runs on both sides, and the new block carries on the list")
    func splitKeepsRuns() throws {
        let block = Block(type: .bulletedList, runs: trail)
        let state = editor(block)
        let target = try #require(state.split(block.id, lines: [head, tail], caret: 0))
        let next = try #require(state.document[target.id])
        #expect(state.document.order == [block.id, next.id])
        #expect(state.document[block.id]?.runs == head)
        #expect(next.runs == tail)
        #expect(next.type == .bulletedList)
        #expect(target.offset == 0)
    }

    @Test("Return at the start of a heading makes room above without touching its runs")
    func returnAtStartKeepsRuns() {
        let heading = Block(type: .heading(level: 2), runs: trail)
        let state = editor(heading)
        let target = state.split(heading.id, lines: [[], trail], caret: 0)
        #expect(target == CaretTarget(id: heading.id, offset: 0))
        #expect(state.document.order.count == 2)
        #expect(state.document.order.last == heading.id)
        #expect(state.document[heading.id]?.runs == trail)
    }

    @Test("Backspace at the start of a block merges both blocks' runs")
    func mergeKeepsRuns() {
        let first = Block(type: .paragraph, runs: head)
        let second = Block(type: .paragraph, runs: tail)
        let state = editor(first, second)
        let target = state.backspaceAtStart(second.id)
        #expect(target == CaretTarget(id: first.id, offset: 12))
        #expect(state.document.order == [first.id])
        #expect(InlineText.coalesced(state.document[first.id]?.runs ?? []) == trail)
    }

    // MARK: Helpers

    /// A block's text view wired up the way `makeUIView` wires it. The view holds its coordinator
    /// weakly, so callers keep the coordinator alive.
    private func textView(
        _ runs: [InlineRun]? = nil, onSplit: @escaping ([[InlineRun]], Int) -> Void = { _, _ in }
    ) -> (BlockUITextView, BlockTextView.Coordinator) {
        let coordinator = BlockTextView(
            runs: runs ?? trail, placeholder: "", font: .systemFont(ofSize: 17), textColor: .label, lineHeight: 28,
            isCode: false, isFocused: true, wantsCaret: true, caretOffset: nil, caretGeneration: 0,
            onTextChange: { _ in }, onFocusChange: { _ in }, onSplit: onSplit,
            onBackspaceAtStart: {}, onIndent: { _ in }
        ).makeCoordinator()
        let view = BlockUITextView()
        view.delegate = coordinator
        view.coordinator = coordinator
        view.configure(font: .systemFont(ofSize: 17), color: .label, lineHeight: 28, placeholder: "")
        view.setRuns(runs ?? trail)
        return (view, coordinator)
    }

    private func editor(_ blocks: Block...) -> CanvasEditorState {
        let state = CanvasEditorState()
        state.document = BlockDocument(blocks: blocks)
        return state
    }
}
