import ComposableArchitecture
import RemoteCore
import SwiftUI
import WebKit

struct RemoteAphroditeView: View {
    let store: StoreOf<RemoteAphroditeFeature>

    var body: some View {
        Group {
            if let app = store.selectedApp {
                VStack(spacing: 0) {
                    HStack {
                        Button("Back", systemImage: "chevron.left") { store.send(.selectApp(nil)) }
                        Spacer()
                        Text(app.title).font(.headline).lineLimit(1)
                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }.padding(.horizontal)
                    RemoteAphroditeRunner(tool: app)
                }
            } else if store.isLoading && store.apps.isEmpty {
                ProgressView("Loading personal tools")
            } else if store.selectedMacID == nil {
                ContentUnavailableView("Select a Mac", systemImage: "desktopcomputer", description: Text("Choose a paired Mac to view its synced Aphrodite personal tools."))
            } else if store.apps.isEmpty {
                ContentUnavailableView("No personal tools yet", systemImage: "sparkles.rectangle.stack", description: Text("Saved Aphrodite personal tools sync automatically when your paired Mac connects. Synced tools remain available when the Mac is offline."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.apps) { app in
                            Button { store.send(.selectApp(app.id)) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "wand.and.stars").font(.title2)
                                        .frame(width: 44, height: 44)
                                        .background(.thinMaterial, in: .rect(cornerRadius: 12))
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(app.title).font(.headline)
                                        Text(app.updatedAt, format: .relative(presentation: .named))
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
                                }
                                .padding().background(.regularMaterial, in: .rect(cornerRadius: 20))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this personal tool")
                        }
                    }
                    .padding().padding(.bottom, RemotePageTabBar.contentBottomInset + 16)
                }
                .refreshable { await store.send(.task).finish() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await store.send(.task).finish() }
    }
}

private struct RemoteAphroditeRunner: UIViewRepresentable {
    let tool: AphroditePersonalTool
    func makeCoordinator() -> Coordinator { Coordinator(tool: tool) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: AphroditeRemoteAppOrigin.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.load(in: webView)
        return webView
    }
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.tool != tool else { return }
        context.coordinator.tool = tool
        context.coordinator.load(in: webView)
    }

    final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate, WKUIDelegate {
        var tool: AphroditePersonalTool
        init(tool: AphroditePersonalTool) { self.tool = tool }
        func load(in webView: WKWebView) {
            let origin = AphroditeRemoteAppOrigin(appID: tool.id)
            webView.loadHTMLString(AphroditeRemoteSandboxDocument.make(origin: origin), baseURL: AphroditeRemoteSandboxDocument.wrapperBaseURL)
        }
        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url,
                  url == AphroditeRemoteAppOrigin(appID: tool.id).indexURL else {
                urlSchemeTask.didFailWithError(URLError(.unsupportedURL)); return
            }
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "text/html; charset=utf-8",
                    "Content-Security-Policy": AphroditeRemoteSandboxDocument.contentSecurityPolicy,
                    "X-Content-Type-Options": "nosniff",
                ]
            ) else {
                urlSchemeTask.didFailWithError(URLError(.badServerResponse)); return
            }
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(Data(tool.html.utf8))
            urlSchemeTask.didFinish()
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let allowed = navigationAction.request.url.map { $0.scheme == AphroditeRemoteAppOrigin.scheme || $0.scheme == "about" } ?? false
            decisionHandler(allowed ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    }
}
