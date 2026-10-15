import SwiftUI

#if os(macOS)
import WebKit

@available(macOS 26.0, *)
public struct SecureAphroditeWebView: NSViewRepresentable {
    public var html: String
    public var onContentHeightChange: @MainActor (CGFloat) -> Void
    public var onContentSizeChange: @MainActor (CGSize) -> Void
    public init(html: String, onContentSizeChange: @escaping @MainActor (CGSize) -> Void = { _ in }, onContentHeightChange: @escaping @MainActor (CGFloat) -> Void = { _ in }) {
        self.html = html
        self.onContentHeightChange = onContentHeightChange
        self.onContentSizeChange = onContentSizeChange
    }

    public func makeCoordinator() -> Coordinator { Coordinator(onContentHeightChange: onContentHeightChange, onContentSizeChange: onContentSizeChange) }
    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.installReporter(in: view.configuration.userContentController)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsLinkPreview = false
        return view
    }
    public func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onContentHeightChange = onContentHeightChange
        context.coordinator.onContentSizeChange = onContentSizeChange
        guard context.coordinator.html != html else { return }
        context.coordinator.html = html
        context.coordinator.beginNavigation(in: view.configuration.userContentController)
        view.loadHTMLString(AphroditeSandboxDocument.make(from: html), baseURL: nil)
    }

    public static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        coordinator.teardown(view.configuration.userContentController)
        view.navigationDelegate = nil
        view.uiDelegate = nil
    }

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private static let contentWorld = WKContentWorld.world(name: "AphroditeHeightReporter")
        private static let handlerName = "heightReporter"
        private static let maximumReportedHeight: CGFloat = 20_000
        var html: String?
        var onContentHeightChange: @MainActor (CGFloat) -> Void
        var onContentSizeChange: @MainActor (CGSize) -> Void
        private var navigationToken = UUID()
        private var previousHeight: CGFloat?
        private var previousSize: CGSize?

        init(onContentHeightChange: @escaping @MainActor (CGFloat) -> Void, onContentSizeChange: @escaping @MainActor (CGSize) -> Void = { _ in }) {
            self.onContentHeightChange = onContentHeightChange
            self.onContentSizeChange = onContentSizeChange
        }

        func installReporter(in controller: WKUserContentController) {
            controller.add(self, contentWorld: Self.contentWorld, name: Self.handlerName)
        }

        func beginNavigation(in controller: WKUserContentController) {
            navigationToken = UUID(); previousHeight = nil; previousSize = nil
            controller.removeAllUserScripts()
            let token = navigationToken.uuidString
            let source = """
            (() => {
              if (window === window.top) return;
              const token = '\(token)'; let frame = 0;
              const report = () => {
                frame = 0;
                const body = document.body; if (!body) return;
                const style = getComputedStyle(body);
                const marginTop = parseFloat(style.marginTop)||0, marginBottom = parseFloat(style.marginBottom)||0;
                const marginLeft = parseFloat(style.marginLeft)||0, marginRight = parseFloat(style.marginRight)||0;
                let bottom = body.getBoundingClientRect().top + (parseFloat(style.paddingTop)||0);
                const bodyRect = body.getBoundingClientRect();
                let right = bodyRect.left + (parseFloat(style.paddingLeft)||0);
                let left = right;
                for (const child of body.children) {
                  const s = getComputedStyle(child); if (s.display === 'none' || s.position === 'fixed') continue;
                  const r = child.getBoundingClientRect();
                  bottom = Math.max(bottom, r.bottom + (parseFloat(s.marginBottom)||0));
                  left = Math.min(left, r.left - (parseFloat(s.marginLeft)||0));
                  right = Math.max(right, r.right + (parseFloat(s.marginRight)||0));
                }
                const range = document.createRange(); range.selectNodeContents(body);
                for (const r of range.getClientRects()) { bottom = Math.max(bottom, r.bottom); left = Math.min(left, r.left); right = Math.max(right, r.right); }
                const top = bodyRect.top;
                const height = Math.min(\(Int(Self.maximumReportedHeight)), Math.max(1, Math.ceil(marginTop + bottom - top + (parseFloat(style.paddingBottom)||0) + marginBottom)));
                const width = Math.min(\(Int(Self.maximumReportedHeight)), Math.max(1, Math.ceil(marginLeft + right - left + (parseFloat(style.paddingLeft)||0) + (parseFloat(style.paddingRight)||0) + marginRight)));
                if (Number.isFinite(width) && Number.isFinite(height))
                  window.webkit?.messageHandlers?.heightReporter?.postMessage({token, width, height});
              };
              const schedule = () => { if (!frame) frame = setTimeout(report, 16); };
              const resize = new ResizeObserver(schedule);
              const observeChildren = () => {
                resize.disconnect(); resize.observe(document.body);
                for (const child of document.body.children) resize.observe(child);
              };
              const mutations = new MutationObserver(() => { observeChildren(); schedule(); });
              const start = () => { observeChildren(); mutations.observe(document.body,{childList:true,subtree:true,attributes:true,characterData:true}); report(); document.fonts?.ready.then(schedule); addEventListener('load', schedule, true); schedule(); };
              if (document.readyState === 'loading') addEventListener('DOMContentLoaded', start, {once:true}); else start();
              addEventListener('pagehide', () => { resize.disconnect(); mutations.disconnect(); if(frame) clearTimeout(frame); }, {once:true});
            })();
            """
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: Self.contentWorld))
        }

        func teardown(_ controller: WKUserContentController) {
            controller.removeAllUserScripts()
            controller.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: Self.contentWorld)
            onContentHeightChange = { _ in }
            onContentSizeChange = { _ in }
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
            if let size = AphroditeContentSizeReport.parse(message: body, expectedNavigationToken: navigationToken, maximumDimension: Self.maximumReportedHeight),
               AphroditeContentSizeReport.shouldReport(previous: previousSize, next: size) {
                previousSize = size
                onContentSizeChange(size)
            }
            if let height = AphroditeContentHeightReport.parse(message: body, expectedNavigationToken: navigationToken, maximumHeight: Self.maximumReportedHeight),
               AphroditeContentHeightReport.shouldReport(previous: previousHeight, next: height) {
                previousHeight = height
                onContentHeightChange(height)
            }
        }
        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            let controlled = url == nil || url?.scheme == "about"
            decisionHandler(controlled ? .allow : .cancel)
        }
        public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
            let url = navigationResponse.response.url
            decisionHandler(url == nil || url?.scheme == "about" ? .allow : .cancel)
        }
        public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
        public func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) { completionHandler(nil) }
    }
}
#endif
