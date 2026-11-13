import Combine
import Extensions
import Foundation
import OSLog
import WebKit

/// Owns the browser's web views so pages stay alive while their tab or the popover is closed.
/// At most `BrowserPageCache.capacity` pages are kept; the least recently shown are torn down.
@MainActor
public final class BrowserWebViewPool: ObservableObject {
    public static let shared = BrowserWebViewPool()
    /// Persistent store separate from Safari and Aphrodite; keep stable or users lose their sign-ins.
    static let dataStoreIdentifier = UUID(uuidString: "6B0F3B8E-6C1D-4E7A-9C4B-0D7B2F1A9E51")!

    @Published public private(set) var webViews: [UUID: WKWebView] = [:]
    private var cache = BrowserPageCache()
    private var observations: [UUID: [NSKeyValueObservation]] = [:]
    private var delegates: [UUID: BrowserWebViewDelegate] = [:]
    private var failures: [UUID: String] = [:]
    private var continuation: AsyncStream<BrowserNavigationEvent>.Continuation?
    private lazy var dataStore = WKWebsiteDataStore(forIdentifier: Self.dataStoreIdentifier)

    func makeEventStream() -> AsyncStream<BrowserNavigationEvent> {
        continuation?.finish()
        let (stream, continuation) = AsyncStream.makeStream(
            of: BrowserNavigationEvent.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        self.continuation = continuation
        return stream
    }

    func activate(_ bookmark: BrowserBookmark) {
        if webViews[bookmark.id] == nil {
            let webView = makeWebView(id: bookmark.id, mobile: bookmark.usesMobileUserAgent)
            webViews[bookmark.id] = webView
            webView.load(URLRequest(url: bookmark.url))
        }
        for evicted in cache.touch(bookmark.id) where evicted != bookmark.id {
            discard(evicted)
        }
        publish(bookmark.id)
    }

    func load(_ id: UUID, _ url: URL) { webViews[id]?.load(URLRequest(url: url)) }
    func goBack(_ id: UUID) { webViews[id]?.goBack() }
    func goForward(_ id: UUID) { webViews[id]?.goForward() }
    func reload(_ id: UUID) { webViews[id]?.reload() }
    func stop(_ id: UUID) { webViews[id]?.stopLoading() }

    func setMobileUserAgent(_ id: UUID, _ enabled: Bool) {
        guard let webView = webViews[id] else { return }
        webView.customUserAgent = enabled ? BrowserUserAgent.mobile : nil
        webView.reload()
    }

    func discard(_ id: UUID) {
        cache.remove(id)
        observations[id] = nil
        failures[id] = nil
        guard let webView = webViews.removeValue(forKey: id) else { return }
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        delegates[id] = nil
    }

    func clearWebsiteData() async {
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        Logger.browser.info("Cleared browser website data")
    }

    func recordFailure(_ id: UUID, _ description: String?) {
        guard failures[id] != description else { return }
        failures[id] = description
        publish(id)
    }

    private func makeWebView(id: UUID, mobile: Bool) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.preferences.isElementFullscreenEnabled = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = mobile ? BrowserUserAgent.mobile : nil
        let delegate = BrowserWebViewDelegate(pageID: id, pool: self)
        delegates[id] = delegate
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        // WebKit reports these key paths on the main thread.
        let changed: @Sendable () -> Void = { [weak self] in MainActor.assumeIsolated { self?.publish(id) } }
        observations[id] = [
            webView.observe(\.url) { _, _ in changed() },
            webView.observe(\.title) { _, _ in changed() },
            webView.observe(\.canGoBack) { _, _ in changed() },
            webView.observe(\.canGoForward) { _, _ in changed() },
            webView.observe(\.isLoading) { _, _ in changed() },
            webView.observe(\.estimatedProgress) { _, _ in changed() },
        ]
        return webView
    }

    private func publish(_ id: UUID) {
        guard let webView = webViews[id] else { return }
        continuation?.yield(BrowserNavigationEvent(bookmarkID: id, state: BrowserNavigationState(
            currentURL: webView.url,
            title: webView.title ?? "",
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward,
            isLoading: webView.isLoading,
            progress: webView.estimatedProgress,
            failureDescription: failures[id]
        )))
    }
}

extension BrowserWebClient {
    static let live = BrowserWebClient(
        events: { await MainActor.run { BrowserWebViewPool.shared.makeEventStream() } },
        activate: { bookmark in await MainActor.run { BrowserWebViewPool.shared.activate(bookmark) } },
        load: { id, url in await MainActor.run { BrowserWebViewPool.shared.load(id, url) } },
        goBack: { id in await MainActor.run { BrowserWebViewPool.shared.goBack(id) } },
        goForward: { id in await MainActor.run { BrowserWebViewPool.shared.goForward(id) } },
        reload: { id in await MainActor.run { BrowserWebViewPool.shared.reload(id) } },
        stop: { id in await MainActor.run { BrowserWebViewPool.shared.stop(id) } },
        setMobileUserAgent: { id, enabled in
            await MainActor.run { BrowserWebViewPool.shared.setMobileUserAgent(id, enabled) }
        },
        discard: { id in await MainActor.run { BrowserWebViewPool.shared.discard(id) } },
        clearWebsiteData: { await BrowserWebViewPool.shared.clearWebsiteData() }
    )
}
