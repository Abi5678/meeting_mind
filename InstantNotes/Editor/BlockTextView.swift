//
//  BlockTextView.swift
//  Instant Notes
//
// The editable text inside a block row. UIKit rather than SwiftUI's TextField because a block
// editor needs three things TextField can't give it: Return caught before the newline lands,
// Backspace at the very start of a block (including an empty one, where the text doesn't
// change), and control over where the caret goes when focus moves to a new block.

import SwiftUI
import UIKit

struct BlockTextView: UIViewRepresentable {
    var text: String
    var placeholder: String
    var font: UIFont
    var textColor: UIColor
    /// Every line sits on this pitch, so rows land on the paper's ruling.
    var lineHeight: CGFloat
    /// Code keeps its newlines and tabs instead of splitting into blocks.
    var isCode: Bool
    var isFocused: Bool
    /// Whether this block is the one the editor wants the caret in.
    var wantsCaret: Bool
    /// Where the caret goes when focus arrives here programmatically; nil puts it at the end.
    var caretOffset: Int?
    /// Bumped by the editor on every deliberate focus move, so a caret is placed exactly once
    /// and typing is never interrupted by a stale offset being re-applied.
    var caretGeneration: Int

    var onTextChange: (String) -> Void
    var onFocusChange: (Bool) -> Void
    /// Return or a multi-line paste: the block's text cut at each newline, and the caret's
    /// offset into the last piece.
    var onSplit: ([String], Int) -> Void
    var onBackspaceAtStart: () -> Void
    /// Tab (true) and Shift-Tab (false) on a hardware keyboard.
    var onIndent: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> BlockUITextView {
        let view = BlockUITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: BlockUITextView, context: Context) {
        context.coordinator.parent = self
        view.textContainerInset = isCode ? UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10) : .zero
        view.configure(font: font, color: textColor, lineHeight: isCode ? nil : lineHeight, placeholder: placeholder)
        view.setLiteral(isCode)

        // A bumped generation means the editor reshaped the document — a split, a merge, a turn —
        // so the model is ahead of the view and gets to write both the text and the caret.
        let isStructural = view.appliedGeneration != caretGeneration
        if isStructural {
            view.appliedGeneration = caretGeneration
            if wantsCaret { view.pendingCaret = .some(caretOffset) }
        }

        // Otherwise the focused view owns its text: what the model hands back while someone is
        // typing is a lagging echo of keystrokes that haven't reached it yet, and writing that
        // back would drop and reorder them.
        if view.text != text, view.markedTextRange == nil, isStructural || !isFocused {
            view.setText(text)
        }

        view.wantsFocus = isFocused
        if isFocused, isStructural || (!view.isFirstResponder && !view.yielded) {
            view.applyFocus()
            // A row made in this same update isn't in a window yet; `didMoveToWindow` picks it
            // up when it lands, so focus survives a navigation push.
            if !view.isFirstResponder {
                DispatchQueue.main.async { [weak view] in view?.applyFocus() }
            }
        } else if !isFocused, view.isFirstResponder {
            // Two turns later, so a block taking focus claims first responder first and the
            // keyboard never drops between blocks.
            DispatchQueue.main.async {
                DispatchQueue.main.async { [weak view] in
                    guard let view, !view.wantsFocus, view.isFirstResponder else { return }
                    view.resignFirstResponder()
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BlockUITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        // Whole rows of ruling, so the next block starts on a line.
        guard lineHeight > 0 else { return CGSize(width: width, height: fitted) }
        let rows = max(1, (fitted / lineHeight - 0.01).rounded(.up))
        return CGSize(width: width, height: rows * lineHeight)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView

        init(_ parent: BlockTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            (textView as? BlockUITextView)?.updatePlaceholder()
            parent.onTextChange(textView.text)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            (textView as? BlockUITextView)?.yielded = false
            (textView as? BlockUITextView)?.handedOff = false
            parent.onFocusChange(true)
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            (textView as? BlockUITextView)?.yielded = true
            (textView as? BlockUITextView)?.handedOff = false
            parent.onFocusChange(false)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Keys typed between a Return and the new block taking focus belong to the new block.
            if let view = textView as? BlockUITextView, view.handedOff || BlockUITextView.replayScheduled {
                if BlockUITextView.handoffIsFresh {
                    BlockUITextView.carryOver += text
                    return false
                }
                // The new block never took focus; type here rather than buffer forever.
                view.handedOff = false
                BlockUITextView.carryOver = ""
            }
            guard !parent.isCode else { return true }
            if text == "\t" {
                parent.onIndent(true)
                return false
            }
            guard text.contains(where: \.isNewline) else { return true }

            let current = textView.text as NSString
            let updated = current.replacingCharacters(in: range, with: text)
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\u{2028}", with: "\n")
            let lines = updated.components(separatedBy: "\n")
            let trailing = current.substring(from: NSMaxRange(range)) as NSString
            let caret = max(0, (lines[lines.count - 1] as NSString).length - trailing.length)
            (textView as? BlockUITextView)?.handedOff = true
            BlockUITextView.handoffAt = .now
            parent.onSplit(lines, caret)
            return false
        }

        func backspaceAtStart() { parent.onBackspaceAtStart() }
        func outdent() { parent.onIndent(false) }
    }
}

/// UITextView that reports Backspace at offset zero and Shift-Tab, and draws its own placeholder.
final class BlockUITextView: UITextView {
    weak var coordinator: BlockTextView.Coordinator?
    /// The editor's focus request, kept on the view so a retry never reads a stale struct.
    var wantsFocus = false
    /// Set when focus moved elsewhere (say, the title). Until the editor asks again, an update
    /// must not pull it back.
    var yielded = false
    /// A caret placement the editor asked for and this view hasn't applied yet. The outer
    /// optional is whether one is pending; the inner one is where (nil = the end of the text).
    var pendingCaret: Int??
    var appliedGeneration = -1
    /// Set once this block has split, until focus leaves it for the new block.
    var handedOff = false
    /// What was typed while focus was in flight after a split; the next block to take focus types it.
    static var carryOver = ""
    /// A replay of `carryOver` is queued; keys arriving meanwhile join the queue so order holds.
    static var replayScheduled = false
    static var handoffAt = Date.distantPast
    /// Focus lands within a frame or two of a split. Anything older is left over, and must not
    /// be typed into whatever block (or note) takes focus next.
    static var handoffIsFresh: Bool { Date.now.timeIntervalSince(handoffAt) < 1 }
    private let placeholderLabel = UILabel()
    private var attributes: [NSAttributedString.Key: Any] = [:]
    private var configuredKey: String = ""

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(font: UIFont, color: UIColor, lineHeight: CGFloat?, placeholder: String) {
        let key = "\(font.fontName)|\(font.pointSize)|\(color.hash)|\(lineHeight ?? 0)|\(placeholder)"
        guard key != configuredKey else { return }
        configuredKey = key

        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let lineHeight {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            attributes[.paragraphStyle] = paragraph
        }
        self.attributes = attributes
        typingAttributes = attributes

        var placeholderAttributes = attributes
        placeholderAttributes[.foregroundColor] = UIColor.placeholderText
        placeholderLabel.attributedText = NSAttributedString(string: placeholder, attributes: placeholderAttributes)
        accessibilityHint = placeholder

        // Restyle what's already there (a block turned into a heading, a to-do ticked off).
        if !text.isEmpty {
            let selection = selectedRange
            attributedText = NSAttributedString(string: text, attributes: attributes)
            selectedRange = selection
        }
        setNeedsLayout()
    }

    /// Code is typed as-is: no capital on `let`, no curly quotes, no autocorrect.
    func setLiteral(_ literal: Bool) {
        let capitalization: UITextAutocapitalizationType = literal ? .none : .sentences
        guard autocapitalizationType != capitalization else { return }
        autocapitalizationType = capitalization
        autocorrectionType = literal ? .no : .default
        spellCheckingType = literal ? .no : .default
        smartQuotesType = literal ? .no : .default
        smartDashesType = literal ? .no : .default
        if isFirstResponder { reloadInputViews() }
    }

    func setText(_ text: String) {
        // Assigning attributedText drops the selection, so put it back where it was.
        let location = selectedRange.location
        attributedText = NSAttributedString(string: text, attributes: attributes)
        typingAttributes = attributes
        selectedRange = NSRange(location: min(location, (self.text as NSString).length), length: 0)
        updatePlaceholder()
        invalidateIntrinsicContentSize()
    }

    func updatePlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = textContainerInset
        let width = max(0, bounds.width - inset.left - inset.right)
        let height = placeholderLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        placeholderLabel.frame = CGRect(x: inset.left, y: inset.top, width: width, height: height)
        updatePlaceholder()
    }

    /// Takes first responder and, when the editor asked for one, places the caret — exactly once,
    /// so a spent request can never yank the caret out from under someone mid-word.
    func applyFocus() {
        guard wantsFocus, window != nil else { return }
        // A split that keeps the caret here (Return on an empty list item) hands off to itself.
        handedOff = false
        if !isFirstResponder { becomeFirstResponder() }
        if let request = pendingCaret {
            pendingCaret = nil
            let length = (text as NSString).length
            selectedRange = NSRange(location: min(max(request ?? length, 0), length), length: 0)
        }
        // Next turn: this runs inside a SwiftUI update, where the edit's state change would be dropped.
        if !Self.handoffIsFresh { Self.carryOver = "" }
        if isFirstResponder, !Self.carryOver.isEmpty, !Self.replayScheduled {
            Self.replayScheduled = true
            DispatchQueue.main.async { [weak self] in self?.replayCarryOver() }
        }
    }

    /// Types the carried keys up to and including the first Return, as if typed now. That Return
    /// splits again and the next block to take focus picks up the rest.
    private func replayCarryOver() {
        Self.replayScheduled = false
        let carried = Self.carryOver
        guard isFirstResponder, !carried.isEmpty else { return }
        let end = carried.firstIndex(where: \.isNewline).map { carried.index(after: $0) } ?? carried.endIndex
        Self.carryOver = String(carried[end...])
        let typed = String(carried[..<end])
        // insertText skips the delegate, which is where a Return becomes a split, so ask it first.
        if delegate?.textView?(self, shouldChangeTextIn: selectedRange, replacementText: typed) ?? true {
            insertText(typed)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if wantsFocus { applyFocus() }
    }

    override func deleteBackward() {
        if selectedRange.location == 0, selectedRange.length == 0, markedTextRange == nil {
            coordinator?.backspaceAtStart()
            return
        }
        super.deleteBackward()
    }

    override var keyCommands: [UIKeyCommand]? {
        let outdent = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdent))
        outdent.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [outdent]
    }

    @objc private func outdent() { coordinator?.outdent() }
}
