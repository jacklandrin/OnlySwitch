import Foundation
import WebKit

/// A presentation-only renderer. Campaign decisions and native effects belong to the feature.
@MainActor
final class OnlyRemoteCampaignView: WKWebView, WKNavigationDelegate, WKUIDelegate {
    private let onLoaded: () -> Void
    private let onFailed: () -> Void
    private let onDownload: () -> Void
    private var isInitialLoad = true

    init(language: String, onLoaded: @escaping () -> Void, onFailed: @escaping () -> Void, onDownload: @escaping () -> Void) {
        self.onLoaded = onLoaded
        self.onFailed = onFailed
        self.onDownload = onDownload
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let encodedLanguage = (try? JSONEncoder().encode(language))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"en\""
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.onlySwitchLanguage = \(encodedLanguage);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        super.init(frame: .zero, configuration: configuration)
        navigationDelegate = self
        uiDelegate = self
        allowsBackForwardNavigationGestures = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateLanguage(_ language: String) {
        callAsyncJavaScript(
            "if (typeof window.setCampaignLanguage === 'function') { window.setCampaignLanguage(language); }",
            arguments: ["language": language],
            in: nil,
            in: .page,
            completionHandler: nil
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isInitialLoad else { return }
        isInitialLoad = false
        onLoaded()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFailed()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onFailed()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onFailed()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame != false,
           navigationAction.request.url == OnlyRemoteCampaignClient.appStoreURL {
            onDownload()
            return .cancel
        }
        let isInitialDocument = isInitialLoad && navigationAction.navigationType == .other
            && navigationAction.targetFrame?.isMainFrame == true
            && navigationAction.request.url?.absoluteString == "about:blank"
        return isInitialDocument ? .allow : .cancel
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}
