#if os(macOS)
import Foundation
import WebKit

@available(macOS 26.0, *)
@MainActor
final class AphroditeStorageCleanupOperation: NSObject, WKNavigationDelegate {
    private let origin: AphroditeAppOrigin
    private let configuration: WKWebViewConfiguration
    private let schemeHandler: AphroditeStorageCleanupSchemeHandler
    private var webView: WKWebView?
    private var completion: (() -> Void)?

    init(origin: AphroditeAppOrigin) {
        self.origin = origin
        configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        schemeHandler = AphroditeStorageCleanupSchemeHandler(origin: origin)
        super.init()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: AphroditeAppOrigin.scheme)
    }

    func run() async {
        await withCheckedContinuation { continuation in
            start { continuation.resume() }
        }
    }

    func start(completion: @escaping () -> Void) {
        self.completion = completion
        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        webView.navigationDelegate = self
        webView.loadHTMLString(Self.wrapper(origin: origin), baseURL: AphroditeSandboxDocument.wrapperBaseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("new Promise(resolve=>{if(document.title==='aphrodite-storage-cleared')resolve(true);else{addEventListener('aphrodite-storage-cleared',()=>resolve(true),{once:true});setTimeout(()=>resolve(false),5000)}})") { [weak self] _, _ in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finish()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        finish()
    }

    private func finish() {
        guard let completion else { return }
        self.completion = nil
        webView?.navigationDelegate = nil
        webView = nil
        completion()
    }

    private static func wrapper(origin: AphroditeAppOrigin) -> String {
        """
        <!doctype html><meta charset="utf-8"><title>Storage cleanup</title>
        <script>addEventListener('message',event=>{if(event.source===document.querySelector('iframe').contentWindow&&event.data==='aphrodite-storage-cleared'){document.title='aphrodite-storage-cleared';dispatchEvent(new Event('aphrodite-storage-cleared'))}})</script>
        <iframe sandbox="allow-scripts allow-same-origin" src="\(origin.indexURL.absoluteString)"></iframe>
        """
    }
}

@available(macOS 26.0, *)
@MainActor
private final class AphroditeStorageCleanupSchemeHandler: NSObject, WKURLSchemeHandler {
    private let origin: AphroditeAppOrigin

    init(origin: AphroditeAppOrigin) {
        self.origin = origin
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard urlSchemeTask.request.url == origin.indexURL,
              let response = HTTPURLResponse(
                url: origin.indexURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "text/html; charset=utf-8",
                    "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
                    "X-Content-Type-Options": "nosniff",
                ]
              ) else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let document = "<!doctype html><title>Storage cleanup</title><script>localStorage.clear();parent.postMessage('aphrodite-storage-cleared','*')</script>"
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(Data(document.utf8))
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
#endif
