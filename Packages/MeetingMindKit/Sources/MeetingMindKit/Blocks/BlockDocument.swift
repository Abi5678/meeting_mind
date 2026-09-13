import Foundation

/// An ordered, editable sequence of blocks — the pure-model half of a note.
///
/// `SwiftData` owns persistence in the app target; this type only owns ordering and the
/// operations an editor needs (insert, move, indent, split/merge), so those operations can be
/// unit tested without a `ModelContext`.
public struct BlockDocument: Equatable, Sendable {
    private(set) public var blocksByID: [UUID: Block]
    private(set) public var order: [UUID]

    public init(blocks: [Block] = []) {
        blocksByID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        order = blocks.map(\.id)
    }

    public var blocks: [Block] {
        order.compactMap { blocksByID[$0] }
    }

    public var isEmpty: Bool { order.isEmpty }
    public var count: Int { order.count }

    public subscript(id: UUID) -> Block? {
        blocksByID[id]
    }

    /// The whole document's text, one block per line, for search indexing.
    public var plainText: String {
        blocks.map(\.plainText).joined(separator: "\n")
    }

    // MARK: - Mutation

    /// Inserts `block` after `id`, or at the start if `id` is `nil` or not found.
    @discardableResult
    public mutating func insert(_ block: Block, after id: UUID?) -> Int {
        blocksByID[block.id] = block
        guard let id, let index = order.firstIndex(of: id) else {
            order.insert(block.id, at: 0)
            return 0
        }
        order.insert(block.id, at: index + 1)
        return index + 1
    }

    public mutating func append(_ block: Block) {
        blocksByID[block.id] = block
        order.append(block.id)
    }

    @discardableResult
    public mutating func remove(_ id: UUID) -> Block? {
        guard let block = blocksByID.removeValue(forKey: id) else { return nil }
        order.removeAll { $0 == id }
        return block
    }

    public mutating func update(_ id: UUID, transform: (inout Block) -> Void) {
        guard var block = blocksByID[id] else { return }
        transform(&block)
        blocksByID[id] = block
    }

    /// Moves the block at `sourceIndex` so it ends up at `destinationIndex` in the *original*
    /// ordering — matching the semantics of `List.onMove` / `NSCollectionView` drag-reorder,
    /// where the destination index is expressed against the pre-move array.
    public mutating func move(fromIndex sourceIndex: Int, toIndex destinationIndex: Int) {
        guard order.indices.contains(sourceIndex) else { return }
        let clampedDestination = min(max(destinationIndex, 0), order.count)

        let id = order.remove(at: sourceIndex)
        let adjustedDestination = sourceIndex < clampedDestination ? clampedDestination - 1 : clampedDestination
        order.insert(id, at: adjustedDestination)
    }

    /// Splits the block at `id` into two at `runOffset` UTF-16 code units into its plain text.
    /// The new block inherits the original's type; returns the new block's id, or `nil` if `id`
    /// was not found.
    ///
    /// This is what pressing Return mid-block does: everything before the cursor stays, and
    /// everything after becomes a fresh sibling block directly beneath it.
    @discardableResult
    public mutating func split(_ id: UUID, atRunOffset runOffset: Int) -> UUID? {
        guard let block = blocksByID[id] else { return nil }

        let text = block.plainText
        let clamped = min(max(runOffset, 0), text.utf16.count)
        guard let splitIndex = text.utf16Index(atOffset: clamped) else { return nil }

        let before = String(text[text.startIndex..<splitIndex])
        let after = String(text[splitIndex...])

        blocksByID[id]?.runs = before.isEmpty ? [] : [.plain(before)]

        var newBlock = Block(type: block.type, indent: block.indent)
        newBlock.runs = after.isEmpty ? [] : [.plain(after)]
        insert(newBlock, after: id)
        return newBlock.id
    }

    /// Merges the block at `id` into its preceding sibling (Backspace at position zero).
    /// Returns the surviving block's id, or `nil` if `id` is the first block or not found.
    @discardableResult
    public mutating func mergeWithPrevious(_ id: UUID) -> UUID? {
        guard let index = order.firstIndex(of: id), index > 0 else { return nil }
        let previousID = order[index - 1]

        guard let current = blocksByID[id], let previous = blocksByID[previousID] else { return nil }

        blocksByID[previousID]?.runs = previous.runs + current.runs
        remove(id)
        return previousID
    }
}

private extension String {
    /// The `String.Index` at the given UTF-16 offset, or `nil` if the offset lands mid-surrogate-pair.
    func utf16Index(atOffset offset: Int) -> Index? {
        utf16.index(utf16.startIndex, offsetBy: offset, limitedBy: utf16.endIndex)
            .flatMap { Index($0, within: self) }
    }
}
