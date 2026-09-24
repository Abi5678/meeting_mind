//
//  NotePDFExporter.swift
//  Instant Notes
//
// Exports the page as it looks on screen — paper, text and ink — as a PDF.

import SwiftUI
import UIKit

/// The editor's UIScrollView, found once the page is on screen.
@MainActor
final class EditorScrollHandle {
    weak var scrollView: UIScrollView?
}

/// Put in the scroll view's content; hands the enclosing UIScrollView to `handle`.
struct EnclosingScrollViewFinder: UIViewRepresentable {
    let handle: EditorScrollHandle

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.handle = handle
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: FinderView, context: Context) {}

    final class FinderView: UIView {
        var handle: EditorScrollHandle?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var view = superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            if let scrollView = view as? UIScrollView { handle?.scrollView = scrollView }
        }
    }
}

@MainActor
enum NotePDFExporter {
    /// Scrolls through the page one screen at a time and draws each screen onto a PDF page.
    /// SwiftUI's ImageRenderer can't draw the UIKit text views or the ink, so this snapshots
    /// the real views; the text in the PDF is an image, not selectable.
    static func pdf(of scrollView: UIScrollView, height: CGFloat, background: UIColor, title: String) -> Data {
        let pageSize = scrollView.bounds.size
        let savedOffset = scrollView.contentOffset
        let showedIndicator = scrollView.showsVerticalScrollIndicator
        scrollView.showsVerticalScrollIndicator = false
        // The fade under the toolbar would otherwise wash out the top of every page.
        var hiddenEdgeEffects: [AnyObject] = []
        if #available(iOS 26, *) {
            for effect in [scrollView.topEdgeEffect, scrollView.bottomEdgeEffect] where !effect.isHidden {
                effect.isHidden = true
                hiddenEdgeEffects.append(effect)
            }
        }
        defer {
            scrollView.contentOffset = savedOffset
            scrollView.showsVerticalScrollIndicator = showedIndicator
            if #available(iOS 26, *) {
                hiddenEdgeEffects.forEach { ($0 as? UIScrollEdgeEffect)?.isHidden = false }
            }
        }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Quolio"]
        let pageCount = max(1, Int((height / pageSize.height).rounded(.up)))
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            for page in 0..<pageCount {
                context.beginPage()
                background.setFill()
                context.fill(CGRect(origin: .zero, size: pageSize))
                scrollView.contentOffset = CGPoint(x: 0, y: CGFloat(page) * pageSize.height)
                scrollView.layoutIfNeeded()
                scrollView.drawHierarchy(in: CGRect(origin: .zero, size: pageSize), afterScreenUpdates: true)
            }
        }
    }

    /// Writes `data` to a temporary `<name>.pdf` and opens the share sheet from `sourceView`.
    static func share(_ data: Data, name: String, from sourceView: UIView) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name).appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url)

        guard var presenter = sourceView.window?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad and Mac show the sheet as a popover; anchor it at the top trailing corner, near the More button.
        sheet.popoverPresentationController?.sourceView = sourceView
        sheet.popoverPresentationController?.sourceRect = CGRect(x: sourceView.bounds.maxX - 44, y: sourceView.bounds.minY, width: 1, height: 1)
        presenter.present(sheet, animated: true)
    }
}
