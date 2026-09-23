//
//  BlockType+Extensions.swift
//  Instant Notes
//
// UI helpers for BlockType — icons, placeholders, titles.

import SwiftUI
import MeetingMindKit

extension BlockType {
    /// SF Symbol name for this block type's icon in toolbars and menus.
    var iconName: String {
        switch self {
        case .paragraph: return "textformat"
        case .heading(level: 1): return "1.square"
        case .heading(level: 2): return "2.square"
        case .heading: return "3.square"
        case .bulletedList: return "list.bullet"
        case .numberedList: return "list.number"
        case .todo: return "checkmark.circle"
        case .toggle: return "chevron.right.circle"
        case .quote: return "text.quote"
        case .callout: return "lightbulb"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .divider: return "minus"
        }
    }

    /// Placeholder text for a new block of this type.
    var defaultPlaceholder: String {
        switch self {
        case .paragraph: return "Type something…"
        case .heading(level: _): return "Heading"
        case .bulletedList: return "Item"
        case .numberedList: return "List item"
        case .todo: return "Todo"
        case .toggle: return "Toggle content"
        case .quote: return "Quoted text"
        case let .callout(emoji):
            if emoji.isEmpty { return "Callout text" }
            return "\(emoji) Callout text"
        case let .code(lang):
            if let lang, !lang.isEmpty {
                return "// \(lang.capitalized) code here…"
            }
            return "// Code here…"
        case .divider: return ""
        }
    }

    /// Human-readable display name for menus and settings.
    var displayName: String {
        switch self {
        case .paragraph: "Text"
        case .heading(let level): "Heading \(level)"
        case .bulletedList: "Bullet List"
        case .numberedList: "Numbered List"
        case .todo: "Todo"
        case .toggle: "Toggle"
        case .quote: "Quote"
        case .callout: "Callout"
        case .code: "Code"
        case .divider: "Divider"
        }
    }

    /// Whether this block type renders as a heading for typography purposes.
    var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }

    /// Code keeps its own newlines and tabs instead of splitting into blocks.
    var isCode: Bool {
        if case .code = self { return true }
        return false
    }

    /// Whether Return at the end of this block starts another one just like it.
    var continuesOnReturn: Bool {
        switch self {
        case .bulletedList, .numberedList, .todo: return true
        default: return false
        }
    }

    /// What the block Return creates below this one becomes.
    var continuation: BlockType {
        continuesOnReturn ? self : .paragraph
    }
}
