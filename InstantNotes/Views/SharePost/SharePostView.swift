//
//  SharePostView.swift
//  Instant Notes
//
// Turns a note into a social post: edit the text, pick the photos, then share to LinkedIn,
// X or any app on the share sheet.

import SwiftUI
import UIKit
import MeetingMindKit

struct SharePostView: View {
    let tags: [String]
    let images: [UIImage]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var text: String
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var included: Set<Int>
    @State private var copiedNotice: String?

    init(title: String, document: BlockDocument, tags: [String], images: [UIImage]) {
        self.tags = tags
        self.images = images
        _text = State(initialValue: Self.draft(title: title, document: document))
        _included = State(initialValue: Set(images.indices))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    editor
                    counters
                    if !images.isEmpty { photoStrip }
                    destinations
                }
                .padding(16)
            }
            .navigationTitle("Share as post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let copiedNotice {
                    Text(copiedNotice)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            PostTextView(text: $text, selection: $selection)
                .frame(minHeight: 260)
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 8) {
                styleButton("bold", "Bold", .bold)
                styleButton("italic", "Italic", .italic)
                if !tags.isEmpty {
                    Button { addHashtags() } label: {
                        Label("Hashtags", systemImage: "number")
                    }
                }
                Spacer()
                Button { copy("Copied") } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)

            Text("Bold and italic use Unicode letters, so they show on LinkedIn and X, where posts have no formatting of their own. Select text first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func styleButton(_ symbol: String, _ label: String, _ style: UnicodeTextStyle.Style) -> some View {
        Button { applyStyle(style) } label: {
            Image(systemName: symbol).frame(minWidth: 20)
        }
        .disabled(selection.length == 0)
        .accessibilityLabel(label)
    }

    private var counters: some View {
        HStack(spacing: 16) {
            counter("LinkedIn", limit: 3000)
            counter("X", limit: 280)
        }
        .font(.caption.monospacedDigit())
    }

    private func counter(_ name: String, limit: Int) -> some View {
        let count = text.count
        return Text("\(name) \(count)/\(limit)")
            .foregroundStyle(count > limit ? Color.red : Color.secondary)
            .accessibilityLabel(count > limit ? "\(count - limit) characters over the \(name) limit" : "\(count) of \(limit) characters for \(name)")
    }

    // MARK: Photos

    private var photoStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photos").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(images.indices, id: \.self) { index in
                        Button { toggle(index) } label: {
                            Image(uiImage: images[index])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .opacity(included.contains(index) ? 1 : 0.35)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: included.contains(index) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(.white, Color.accentColor)
                                        .padding(4)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo \(index + 1)")
                        .accessibilityValue(included.contains(index) ? "Included" : "Left out")
                    }
                }
            }
        }
    }

    private func toggle(_ index: Int) {
        if included.contains(index) { included.remove(index) } else { included.insert(index) }
    }

    // MARK: Destinations

    private var destinations: some View {
        VStack(spacing: 10) {
            Button { shareSheet() } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 10) {
                Button { openComposer(Self.linkedInComposer) } label: {
                    Label("LinkedIn", systemImage: "briefcase.fill").frame(maxWidth: .infinity)
                }
                Button { openComposer(Self.xComposer) } label: {
                    Label("X", systemImage: "xmark").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("Share… sends the text and the checked photos to any app you have, LinkedIn and X included. The LinkedIn and X buttons open their web composer with the text; photos go through Share….")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chosenImages: [UIImage] {
        images.indices.filter(included.contains).map { images[$0] }
    }

    private func shareSheet() {
        let items: [Any] = [text] + chosenImages
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
              var presenter = window.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = presenter.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 80, width: 1, height: 1)
        presenter.present(sheet, animated: true)
    }

    private static let linkedInComposer = "https://www.linkedin.com/feed/?shareActive=true&text="
    private static let xComposer = "https://x.com/intent/post?text="

    /// Copies the text too: LinkedIn sometimes drops prefilled text when it asks you to sign in.
    private func openComposer(_ base: String) {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
        guard let url = URL(string: base + encoded) else { return }
        copy("Text copied, in case you need to paste it")
        openURL(url)
    }

    // MARK: Editing

    private func applyStyle(_ style: UnicodeTextStyle.Style) {
        let ns = text as NSString
        guard selection.length > 0, NSMaxRange(selection) <= ns.length else { return }
        let styled = UnicodeTextStyle.toggle(style, in: ns.substring(with: selection))
        text = ns.replacingCharacters(in: selection, with: styled)
        selection = NSRange(location: selection.location, length: (styled as NSString).length)
    }

    private func addHashtags() {
        let hashtags = tags.map { "#" + $0.replacingOccurrences(of: " ", with: "") }
            .filter { !text.contains($0) }
        guard !hashtags.isEmpty else { return }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + hashtags.joined(separator: " ")
    }

    private func copy(_ notice: String) {
        UIPasteboard.general.string = text
        withAnimation { copiedNotice = notice }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copiedNotice = nil }
        }
    }

    // MARK: Draft

    /// The note as post text: the title, then each block, with lists as bullets and numbers.
    static func draft(title: String, document: BlockDocument) -> String {
        var output = title == "Untitled" ? "" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        var previousWasList = false
        var number = 0

        for block in document.blocks {
            number = block.type == .numberedList ? number + 1 : 0
            let text = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, block.type.holdsText else { continue }
            let indent = String(repeating: "   ", count: block.indent)
            let line: String
            switch block.type {
            case .bulletedList, .toggle: line = indent + "• " + text
            case .numberedList: line = indent + "\(number). " + text
            case .todo: line = indent + (block.isChecked ? "✅ " : "▫️ ") + text
            case .quote: line = "“" + text + "”"
            case let .callout(emoji): line = (emoji.isEmpty ? "💡" : emoji) + " " + text
            default: line = text
            }
            let isList = [BlockType.bulletedList, .numberedList, .todo, .toggle].contains(block.type)
            if !output.isEmpty { output += isList && previousWasList ? "\n" : "\n\n" }
            output += line
            previousWasList = isList
        }
        return output
    }
}

private extension CharacterSet {
    /// A query value can't carry the separators that would end it.
    static let urlQueryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))
}

// MARK: - Text view

/// A plain UITextView, because SwiftUI's TextEditor only reports the selection on iOS 18.
private struct PostTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        view.text = text
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        if view.selectedRange != selection, NSMaxRange(selection) <= (view.text as NSString).length {
            view.selectedRange = selection
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PostTextView
        init(_ parent: PostTextView) { self.parent = parent }

        func textViewDidChange(_ view: UITextView) {
            parent.text = view.text
        }

        func textViewDidChangeSelection(_ view: UITextView) {
            if parent.selection != view.selectedRange { parent.selection = view.selectedRange }
        }
    }
}

// MARK: - Unicode styles

/// LinkedIn and X posts are plain text; people bold and italicise with the Unicode
/// "mathematical" sans-serif letters, which every platform displays.
enum UnicodeTextStyle {
    enum Style { case bold, italic }

    /// Styles `text`, or unstyles it when it is already entirely in `style`.
    static func toggle(_ style: Style, in text: String) -> String {
        let stylable = text.unicodeScalars.filter { styled(plain($0), style) != plain($0) }
        let alreadyStyled = !stylable.isEmpty && stylable.allSatisfy { self.style(of: $0) == style }
        var output = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let base = plain(scalar)
            output.append(alreadyStyled ? base : styled(base, style))
        }
        return String(output)
    }

    private static let boldUpper: UInt32 = 0x1D5D4, boldLower: UInt32 = 0x1D5EE, boldDigit: UInt32 = 0x1D7EC
    private static let italicUpper: UInt32 = 0x1D608, italicLower: UInt32 = 0x1D622

    private static func styled(_ scalar: Unicode.Scalar, _ style: Style) -> Unicode.Scalar {
        let value = scalar.value
        let mapped: UInt32? = switch (style, scalar) {
        case (.bold, "A"..."Z"): boldUpper + value - 65
        case (.bold, "a"..."z"): boldLower + value - 97
        case (.bold, "0"..."9"): boldDigit + value - 48
        case (.italic, "A"..."Z"): italicUpper + value - 65
        case (.italic, "a"..."z"): italicLower + value - 97
        default: nil // italic has no digits
        }
        return mapped.flatMap(Unicode.Scalar.init) ?? scalar
    }

    private static func style(of scalar: Unicode.Scalar) -> Style? {
        let value = scalar.value
        if (boldUpper..<boldUpper + 52).contains(value) || (boldDigit..<boldDigit + 10).contains(value) { return .bold }
        if (italicUpper..<italicUpper + 52).contains(value) { return .italic }
        return nil
    }

    private static func plain(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        let value = scalar.value
        let base: UInt32? = switch value {
        case boldUpper..<boldUpper + 26: 65 + value - boldUpper
        case boldLower..<boldLower + 26: 97 + value - boldLower
        case boldDigit..<boldDigit + 10: 48 + value - boldDigit
        case italicUpper..<italicUpper + 26: 65 + value - italicUpper
        case italicLower..<italicLower + 26: 97 + value - italicLower
        default: nil
        }
        return base.flatMap(Unicode.Scalar.init) ?? scalar
    }
}
