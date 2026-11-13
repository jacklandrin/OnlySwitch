import AppKit
import Extensions
import OSLog
import WebKit

/// Applies `BrowserNavigationPolicy` and keeps popups, downloads and permission prompts out of the panel.
@MainActor
final class BrowserWebViewDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let pageID: UUID
    private weak var pool: BrowserWebViewPool?

    init(pageID: UUID, pool: BrowserWebViewPool) {
        self.pageID = pageID
        self.pool = pool
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        switch BrowserNavigationPolicy.decision(
            for: url,
            isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
            isUserInitiated: navigationAction.navigationType == .linkActivated
        ) {
        case .allow:
            decisionHandler(.allow)
        case .openExternally:
            if let url { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        case .cancel:
            Logger.browser.info("Blocked browser navigation with scheme \(url?.scheme ?? "none", privacy: .public)")
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        guard !navigationResponse.canShowMIMEType else {
            decisionHandler(.allow)
            return
        }
        // Downloads and unsupported files go to the default browser instead of the panel.
        if navigationResponse.isForMainFrame, let url = navigationResponse.response.url,
           BrowserURLNormalizer.allowedSchemes.contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        pool?.recordFailure(pageID, nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        report(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Logger.browser.warning("Browser web content process terminated; reloading")
        webView.reload()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // `target=_blank` and `window.open` load in place; the panel has no second window.
        if navigationAction.targetFrame == nil,
           BrowserNavigationPolicy.decision(for: navigationAction.request.url, isMainFrame: true, isUserInitiated: true) == .allow {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        completionHandler(nil)
    }

    private func report(_ error: any Error) {
        let nsError = error as NSError
        // Cancelled loads and policy-interrupted frames (e.g. a handed-off download) are not failures.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return }
        Logger.browser.error("Browser load failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
        pool?.recordFailure(pageID, nsError.localizedDescription)
    }
}
