import Foundation
import Testing

@testable import MeetingMindKit

@Suite("Block")
struct BlockTests {
    @Test("plainText joins runs with no separator")
    func plainTextJoinsRuns() {
        let block = Block(type: .paragraph, runs: [.plain("Hello, "), InlineRun(text: "world", isBold: true), .plain(".")])
        #expect(block.plainText == "Hello, world.")
    }

    @Test("An empty block has empty plainText")
    func emptyBlock() {
        #expect(Block(type: .paragraph).plainText == "")
    }
}

@Suite("BlockDocument")
struct BlockDocumentTests {
    private func block(_ text: String, type: BlockType = .paragraph, indent: Int = 0) -> Block {
        Block(type: type, runs: [.plain(text)], indent: indent)
    }

    @Test("An empty document has no blocks")
    func emptyDocument() {
        let document = BlockDocument()
        #expect(document.isEmpty)
        #expect(document.count == 0)
        #expect(document.blocks.isEmpty)
        #expect(document.plainText == "")
    }

    @Test("Blocks preserve construction order")
    func preservesOrder() {
        let a = block("First")
        let b = block("Second")
        let document = BlockDocument(blocks: [a, b])

        #expect(document.blocks.map(\.id) == [a.id, b.id])
        #expect(document.plainText == "First\nSecond")
    }

    @Test("Subscript looks up a block by id")
    func subscriptLookup() {
        let a = block("First")
        let document = BlockDocument(blocks: [a])

        #expect(document[a.id]?.plainText == "First")
        #expect(document[UUID()] == nil)
    }

    // MARK: - insert / append / remove

    @Test("Insert after nil places the block first")
    func insertAfterNilIsFirst() {
        var document = BlockDocument(blocks: [block("Existing")])
        let new = block("New")
        let index = document.insert(new, after: nil)

        #expect(index == 0)
        #expect(document.blocks.map(\.plainText) == ["New", "Existing"])
    }

    @Test("Insert after an unknown id places the block first")
    func insertAfterUnknownIDIsFirst() {
        var document = BlockDocument(blocks: [block("Existing")])
        let index = document.insert(block("New"), after: UUID())

        #expect(index == 0)
        #expect(document.blocks.map(\.plainText) == ["New", "Existing"])
    }

    @Test("Insert after a known id places the block immediately after it")
    func insertAfterKnownID() {
        let first = block("First")
        let last = block("Last")
        var document = BlockDocument(blocks: [first, last])

        let index = document.insert(block("Middle"), after: first.id)

        #expect(index == 1)
        #expect(document.blocks.map(\.plainText) == ["First", "Middle", "Last"])
    }

    @Test("Append always places the block last")
    func appendIsLast() {
        var document = BlockDocument(blocks: [block("First")])
        document.append(block("Second"))
        #expect(document.blocks.map(\.plainText) == ["First", "Second"])
    }

    @Test("Remove drops the block from both order and lookup")
    func removeDropsBlock() {
        let a = block("First")
        let b = block("Second")
        var document = BlockDocument(blocks: [a, b])

        let removed = document.remove(a.id)

        #expect(removed?.plainText == "First")
        #expect(document.blocks.map(\.plainText) == ["Second"])
        #expect(document[a.id] == nil)
    }

    @Test("Removing an unknown id is a no-op")
    func removeUnknownIDIsNoOp() {
        var document = BlockDocument(blocks: [block("First")])
        #expect(document.remove(UUID()) == nil)
        #expect(document.count == 1)
    }

    @Test("Update mutates the block in place without moving it")
    func updateMutatesInPlace() {
        let a = block("First")
        let b = block("Second")
        var document = BlockDocument(blocks: [a, b])

        document.update(a.id) { $0.isChecked = true }

        #expect(document[a.id]?.isChecked == true)
        #expect(document.blocks.map(\.id) == [a.id, b.id])
    }

    // MARK: - move

    @Test("Move forward lands one before the naive destination, matching List.onMove semantics")
    func moveForward() {
        var document = BlockDocument(blocks: [block("A"), block("B"), block("C"), block("D")])
        document.move(fromIndex: 0, toIndex: 3)  // "insert A before what is currently index 3"
        #expect(document.blocks.map(\.plainText) == ["B", "C", "A", "D"])
    }

    @Test("Move backward lands exactly at the destination index")
    func moveBackward() {
        var document = BlockDocument(blocks: [block("A"), block("B"), block("C"), block("D")])
        document.move(fromIndex: 3, toIndex: 0)
        #expect(document.blocks.map(\.plainText) == ["D", "A", "B", "C"])
    }

    @Test("Moving a block to its own position is a no-op")
    func moveToSamePosition() {
        var document = BlockDocument(blocks: [block("A"), block("B"), block("C")])
        document.move(fromIndex: 1, toIndex: 1)
        #expect(document.blocks.map(\.plainText) == ["A", "B", "C"])
    }

    @Test("Moving to the end places the block last")
    func moveToEnd() {
        var document = BlockDocument(blocks: [block("A"), block("B"), block("C")])
        document.move(fromIndex: 0, toIndex: 3)
        #expect(document.blocks.map(\.plainText) == ["B", "C", "A"])
    }

    @Test("An out-of-range source index is a no-op")
    func moveOutOfRangeSourceIsNoOp() {
        var document = BlockDocument(blocks: [block("A"), block("B")])
        document.move(fromIndex: 5, toIndex: 0)
        #expect(document.blocks.map(\.plainText) == ["A", "B"])
    }

    // MARK: - split

    @Test("Split mid-block divides the text and inserts a sibling directly after")
    func splitMidBlock() {
        let a = block("HelloWorld")
        var document = BlockDocument(blocks: [a])

        let newID = document.split(a.id, atRunOffset: 5)

        #expect(document[a.id]?.plainText == "Hello")
        #expect(newID != nil)
        #expect(document[newID!]?.plainText == "World")
        #expect(document.blocks.map(\.id) == [a.id, newID!])
    }

    @Test("Split at offset zero leaves the original empty and moves all text to the new block")
    func splitAtStart() {
        let a = block("HelloWorld")
        var document = BlockDocument(blocks: [a])

        let newID = document.split(a.id, atRunOffset: 0)

        #expect(document[a.id]?.plainText == "")
        #expect(document[newID!]?.plainText == "HelloWorld")
    }

    @Test("Split at the end leaves the new block empty")
    func splitAtEnd() {
        let a = block("HelloWorld")
        var document = BlockDocument(blocks: [a])

        let newID = document.split(a.id, atRunOffset: 10)

        #expect(document[a.id]?.plainText == "HelloWorld")
        #expect(document[newID!]?.plainText == "")
    }

    @Test("An out-of-range offset clamps rather than crashing")
    func splitClampsOutOfRangeOffset() {
        let a = block("Hi")
        var document = BlockDocument(blocks: [a])

        let newID = document.split(a.id, atRunOffset: 999)

        #expect(document[a.id]?.plainText == "Hi")
        #expect(document[newID!]?.plainText == "")
    }

    @Test("The new block inherits the original's type and indent")
    func splitInheritsTypeAndIndent() {
        let a = block("HelloWorld", type: .bulletedList, indent: 2)
        var document = BlockDocument(blocks: [a])

        let newID = document.split(a.id, atRunOffset: 5)

        #expect(document[newID!]?.type == .bulletedList)
        #expect(document[newID!]?.indent == 2)
    }

    @Test("Splitting an unknown id returns nil and leaves the document untouched")
    func splitUnknownIDIsNoOp() {
        var document = BlockDocument(blocks: [block("First")])
        #expect(document.split(UUID(), atRunOffset: 0) == nil)
        #expect(document.count == 1)
    }

    @Test("Split handles a multi-byte character without crashing or corrupting text")
    func splitHandlesMultiByteCharacters() {
        let a = block("Caf\u{e9} \u{1F600} World")  // é + 😀
        var document = BlockDocument(blocks: [a])

        // Splitting right after the emoji (a surrogate pair) must not land mid-codepoint.
        let text = a.plainText
        let offset = (text as NSString).range(of: "\u{1F600}").location + 2

        let newID = document.split(a.id, atRunOffset: offset)

        #expect(document[a.id]?.plainText == "Caf\u{e9} \u{1F600}")
        #expect(document[newID!]?.plainText == " World")
    }

    // MARK: - mergeWithPrevious

    @Test("Merge appends the current block's runs onto the previous one and removes it")
    func mergeAppendsAndRemoves() {
        let a = block("Hello")
        let b = block("World")
        var document = BlockDocument(blocks: [a, b])

        let survivorID = document.mergeWithPrevious(b.id)

        #expect(survivorID == a.id)
        #expect(document[a.id]?.plainText == "HelloWorld")
        #expect(document[b.id] == nil)
        #expect(document.count == 1)
    }

    @Test("Merging the first block is a no-op")
    func mergeFirstBlockIsNoOp() {
        let a = block("Only")
        var document = BlockDocument(blocks: [a])

        #expect(document.mergeWithPrevious(a.id) == nil)
        #expect(document.count == 1)
    }

    @Test("Merging an unknown id is a no-op")
    func mergeUnknownIDIsNoOp() {
        var document = BlockDocument(blocks: [block("First"), block("Second")])
        #expect(document.mergeWithPrevious(UUID()) == nil)
        #expect(document.count == 2)
    }

    @Test("Split then merge round-trips back to the original text")
    func splitThenMergeRoundTrips() {
        let a = block("HelloWorld")
        var document = BlockDocument(blocks: [a])

        let newID = document.split(a.id, atRunOffset: 5)!
        document.mergeWithPrevious(newID)

        #expect(document[a.id]?.plainText == "HelloWorld")
        #expect(document.count == 1)
    }
}
