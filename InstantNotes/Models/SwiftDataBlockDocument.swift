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
        BlockDocument(blocks: order.compactMap { blocksByID[$0]?.toBlock() })
    }
}

struct SwiftDataBlock: Codable {
    let id: String
    /// BlockType case name; associated values are stored in the optional fields below.
    let kind: String
    var headingLevel: Int?
    var emoji: String?
    var language: String?
    var imageID: String?
    let runs: [SwiftDataInlineRun]
    let indent: Int
    let isExpanded: Bool
    let isChecked: Bool
    /// Optional so notes saved before audio marks existed still decode.
    var audioMark: AudioMark?
    /// Optional for the same reason.
    var minY: Double?

    init(_ block: Block) {
        self.id = block.id.uuidString
        switch block.type {
        case .paragraph: kind = "paragraph"
        case .heading(let level): kind = "heading"; headingLevel = level
        case .bulletedList: kind = "bulletedList"
        case .numberedList: kind = "numberedList"
        case .todo: kind = "todo"
        case .toggle: kind = "toggle"
        case .quote: kind = "quote"
        case .callout(let emoji): kind = "callout"; self.emoji = emoji
        case .code(let language): kind = "code"; self.language = language
        case .divider: kind = "divider"
        case .image(let id): kind = "image"; imageID = id.uuidString
        }
        self.runs = block.runs.map(SwiftDataInlineRun.init)
        self.indent = block.indent
        self.isExpanded = block.isExpanded
        self.isChecked = block.isChecked
        self.audioMark = block.audioMark
        self.minY = block.minY
    }

    func toBlock() -> Block {
        let type: BlockType = switch kind {
        case "heading": .heading(level: headingLevel ?? 1)
        case "bulletedList": .bulletedList
        case "numberedList": .numberedList
        case "todo": .todo
        case "toggle": .toggle
        case "quote": .quote
        case "callout": .callout(emoji: emoji ?? "")
        case "code": .code(language: language)
        case "divider": .divider
        case "image": imageID.flatMap(UUID.init(uuidString:)).map { .image(id: $0) } ?? .paragraph
        default: .paragraph
        }
        return Block(
            id: UUID(uuidString: id) ?? UUID(),
            type: type,
            runs: runs.map { $0.toInlineRun() },
            indent: indent,
            isExpanded: isExpanded,
            isChecked: isChecked,
            audioMark: audioMark,
            minY: minY
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
