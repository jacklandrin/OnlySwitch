#if os(macOS)
import Foundation
import RemoteCore
import WebKit

@available(macOS 26.0, *)
@MainActor
final class AphroditeGeneratedDocumentSchemeHandler: NSObject, WKURLSchemeHandler {
    private var appID: UUID
    private var html: String

    init(app: AphroditeApp) {
        appID = app.id
        html = app.html
    }

    func update(app: AphroditeApp) {
        appID = app.id
        html = app.html
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let origin = AphroditeAppOrigin(appID: appID)
        guard urlSchemeTask.request.url == origin.indexURL,
              let response = HTTPURLResponse(
                url: origin.indexURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "text/html; charset=utf-8",
                    "Content-Security-Policy": AphroditeRemoteSandboxDocument.contentSecurityPolicy,
                    "X-Content-Type-Options": "nosniff",
                ]
              ) else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(Data(html.utf8))
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
#endif
