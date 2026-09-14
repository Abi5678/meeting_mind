//
//  SwiftDataBlockDocument.swift
//  Instant Notes
//
// Codable wrapper for BlockDocument so it can be stored as JSON in SwiftData.

import Foundation
import MeetingMindKit

struct SwiftDataBlockDocument: Codable {
    let blocksByID: [String: SwiftDataBlock] // keyed by UUID string
    let order: [String] // UUID strings in order

    init(document: BlockDocument) {
        blocksByID = Dictionary(uniqueKeysWithValues: document.blocksByID.map { ($0.key.uuidString, SwiftDataBlock($0.value)) })
        order = document.order.map { $0.uuidString }
    }

    var document: BlockDocument {
        let blocks = blocksByID.compactMapValues { SwiftDataBlock($0).toBlock() }
        let order = order.compactMap { UUID(uuidString: $0) }
        return BlockDocument(blocks: blocks.values.map { $0 })
    }
}

struct SwiftDataBlock: Codable {
    let id: String
    let typeRawValue: Int
    let runs: [SwiftDataInlineRun]
    let indent: Int
    let isExpanded: Bool
    let isChecked: Bool

    init(_ block: Block) {
        self.id = block.id.uuidString
        self.typeRawValue = block.type.rawValue
        self.runs = block.runs.map(SwiftDataInlineRun.init)
        self.indent = block.indent
        self.isExpanded = block.isExpanded
        self.isChecked = block.isChecked
    }

    func toBlock() -> Block {
        let type: BlockType = BlockType(rawValue: typeRawValue) ?? .paragraph
        return Block(
            id: UUID(uuidString: id) ?? UUID(),
            type: type,
            runs: runs.map { SwiftDataInlineRun($0).toInlineRun() },
            indent: indent,
            isExpanded: isExpanded,
            isChecked: isChecked
        )
    }
}

struct SwiftDataInlineRun: Codable {
    let text: String
    let isBold: Bool
    let isItalic: Bool
    let isCode: Bool
    let linkURLString: String?

    init(_ run: InlineRun) {
        self.text = run.text
        self.isBold = run.isBold
        self.isItalic = run.isItalic
        self.isCode = run.isCode
        self.linkURLString = run.linkURL?.absoluteString
    }

    func toInlineRun() -> InlineRun {
        InlineRun(
            text: text,
            isBold: isBold,
            isItalic: isItalic,
            isCode: isCode,
            linkURL: linkURLString.flatMap { URL(string: $0) }
        )
    }
}
