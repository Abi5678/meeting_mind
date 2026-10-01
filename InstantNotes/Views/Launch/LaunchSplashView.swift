//
//  LaunchSplashView.swift
//  InstantNotes
//
//  Plays the Quolio opening animation once on launch: a notebook turns its pages, closes with a
//  wink and reveals the name. The animation is Brand/splash (canvas), built into
//  QuolioSplash.html and shown in a web view so the app plays exactly what the design shows.
//

import SwiftUI
import WebKit

/// Plays the opening animation once, then gets out of the way.
struct LaunchSplashView: View {
    /// Called when the splash has faded out and can be removed.
    var onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var leaving = false

    /// The animation runs 5.8 s, after a web view start-up that can take a couple of seconds on a
    /// cold launch; this is the most we wait before moving on regardless.
    private static let longestWait = 12.0
    /// The finished logo is held for a beat before it leaves.
    private static let hold = 0.6
    private static let fade = 0.35

    var body: some View {
        ZStack {
            Color("PaperBackground")
                .ignoresSafeArea()
            SplashWebView(dark: colorScheme == .dark, onComplete: { finish() }, onFailure: { finish(after: 0) })
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .opacity(leaving ? 0 : 1)
        // A tap skips the rest, so a long animation never stands between someone and their notes.
        .contentShape(Rectangle())
        .onTapGesture { finish(after: 0) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quolio")
        .task {
            try? await Task.sleep(for: .seconds(Self.longestWait))
            finish(after: 0)
        }
    }

    private func finish(after delay: Double = LaunchSplashView.hold) {
        guard !leaving else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !leaving else { return }
            withAnimation(.easeOut(duration: Self.fade)) { leaving = true }
            try? await Task.sleep(for: .seconds(Self.fade))
            onFinish()
        }
    }
}

/// The animation page in a transparent web view, so the app's paper colour shows through.
private struct SplashWebView: UIViewRepresentable {
    let dark: Bool
    let onComplete: () -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "quolioDone")
        // Added before the page's own script runs, so an instant completion (reduced motion) is seen.
        controller.addUserScript(WKUserScript(
            source: "window.addEventListener('quolio:complete',()=>window.webkit.messageHandlers.quolioDone.postMessage(0));",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let config = WKWebViewConfiguration()
        config.userContentController = controller

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.isUserInteractionEnabled = false
        web.navigationDelegate = context.coordinator

        guard let url = Bundle.main.url(forResource: "QuolioSplash", withExtension: "html"),
              var html = try? String(contentsOf: url, encoding: .utf8) else {
            DispatchQueue.main.async(execute: onFailure)
            return web
        }
        // Clear background so the paper colour under it shows; hide the preview's Replay button.
        html = html.replacingOccurrences(of: "--quolio-background:#F6F3EC", with: "--quolio-background:transparent")
        html = html.replacingOccurrences(of: "</style>", with: "#replay{display:none!important}</style>")
        if dark {
            // The name is drawn in ink, which would vanish on the dark paper.
            html = html.replacingOccurrences(of: "#3C3835", with: "#F3EEE6")
        }
        web.loadHTMLString(html, baseURL: nil)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "quolioDone")
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let onComplete: () -> Void
        private let onFailure: () -> Void

        init(onComplete: @escaping () -> Void, onFailure: @escaping () -> Void) {
            self.onComplete = onComplete
            self.onFailure = onFailure
        }

        nonisolated func userContentController(_ userContentController: WKUserContentController,
                                               didReceive message: WKScriptMessage) {
            MainActor.assumeIsolated { onComplete() }
        }

        nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            MainActor.assumeIsolated { onFailure() }
        }

        nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                                 withError error: any Error) {
            MainActor.assumeIsolated { onFailure() }
        }
    }
}
