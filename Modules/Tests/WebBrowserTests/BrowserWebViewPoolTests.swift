#if os(macOS)
import AppKit
import ComposableArchitecture
import Foundation
import Network
import SwiftUI
import Testing
import WebKit
@testable import WebBrowser

@MainActor
struct BrowserWebViewPoolTests {
    @Test(.timeLimit(.minutes(1)))
    func lightWebsitesConvertToDarkAndRestoreWithoutReloadingOrInvertingImages() async throws {
        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        let pool = BrowserWebViewPool(initialAppearance: { darkAppearance })
        let bookmark = BrowserBookmark(
            id: UUID(), title: "Light-only fixture", url: try #require(URL(string: "about:blank"))
        )
        pool.activate(bookmark)
        let webView = try #require(pool.webViews[bookmark.id])
        webView.navigationDelegate = nil
        let hostingView = NSHostingView(rootView: BrowserWebViewHost(pool: pool, bookmarkID: bookmark.id)
            .environment(\.colorScheme, .dark))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 375, height: 667),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer {
            window.close()
            pool.discard(bookmark.id)
        }
        hostingView.layoutSubtreeIfNeeded()
        webView.loadHTMLString("""
            <!doctype html><html><head><style>
            html, body { background: #fff; color: #000; }
            </style></head><body id="light-only-fixture">
            <p>This website has no native dark theme.</p>
            <img id="picture" width="20" height="20" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='20' height='20'%3E%3Crect width='20' height='20' fill='red'/%3E%3C/svg%3E">
            <script>window.reloadSentinel = 'preserved';</script>
            </body></html>
            """, baseURL: nil)
        try await eventually {
            (try? await evaluate("document.body?.id", in: webView)) == "light-only-fixture"
        }
        try await eventually {
            (try? await evaluate("""
                String(Math.max(...getComputedStyle(document.body).backgroundColor.match(/\\d+/g).slice(0, 3).map(Number)) < 80)
                """, in: webView)) == "true"
        }
        #expect(try await evaluate("""
            String(Math.min(...getComputedStyle(document.body).color.match(/\\d+/g).slice(0, 3).map(Number)) > 180)
            """, in: webView) == "true")
        let originalImage = try await evaluate("document.querySelector('#picture').getAttribute('src')", in: webView)
        #expect(try await evaluate("getComputedStyle(document.querySelector('#picture')).filter", in: webView) == "none")
        #expect(try await evaluate("getComputedStyle(document.body).filter", in: webView) == "none")

        // Drain startup callbacks, then simulate dropped media events and background timer
        // throttling. The host must explicitly synchronize appearance into the isolated world.
        _ = try await evaluate("void setTimeout(() => { window.timerBarrier = 'ready'; }, 0)", in: webView, world: .defaultClient)
        try await eventually {
            (try? await evaluate("window.timerBarrier", in: webView, world: .defaultClient)) == "ready"
        }
        _ = try await evaluate("window.originalSetTimeout = globalThis.setTimeout; globalThis.setTimeout = () => -1; ''", in: webView, world: .defaultClient)
        try #require(try await evaluate("typeof onlySwitchBrowserAppearance.updateAppearance", in: webView, world: .defaultClient) == "function")
        _ = try await evaluate("onlySwitchBrowserAppearance.preference.removeEventListener('change', onlySwitchBrowserAppearance.updateAppearance); ''", in: webView, world: .defaultClient)


        hostingView.rootView = BrowserWebViewHost(pool: pool, bookmarkID: bookmark.id)
            .environment(\.colorScheme, .light)
        hostingView.layoutSubtreeIfNeeded()
        try await eventually {
            (try? await evaluate("getComputedStyle(document.body).backgroundColor", in: webView)) == "rgb(255, 255, 255)"
        }
        #expect(try await evaluate("getComputedStyle(document.body).color", in: webView) == "rgb(0, 0, 0)")
        #expect(try await evaluate("document.querySelector('#picture').getAttribute('src')", in: webView) == originalImage)
        #expect(try await evaluate("window.reloadSentinel", in: webView) == "preserved")
        #expect(pool.webViews[bookmark.id] === webView)
        #expect(try await evaluate("String(DarkReader.isEnabled())", in: webView, world: .defaultClient) == "false")
        _ = try await evaluate("globalThis.setTimeout = window.originalSetTimeout; delete window.originalSetTimeout; ''", in: webView, world: .defaultClient)
        _ = try await evaluate("void fetch('data:text/plain,ok').then(response => response.text()).then(text => { window.pageFetchResult = text; })", in: webView)
        try await eventually { (try? await evaluate("window.pageFetchResult", in: webView)) == "ok" }

        hostingView.rootView = BrowserWebViewHost(pool: pool, bookmarkID: bookmark.id)
            .environment(\.colorScheme, .dark)
        hostingView.layoutSubtreeIfNeeded()
        try await eventually {
            (try? await evaluate("""
                String(Math.max(...getComputedStyle(document.body).backgroundColor.match(/\\d+/g).slice(0, 3).map(Number)) < 80)
                """, in: webView)) == "true"
        }
        #expect(try await evaluate("window.reloadSentinel", in: webView) == "preserved")
        #expect(try await evaluate("getComputedStyle(document.querySelector('#picture')).filter", in: webView) == "none")
    }

    @Test(.timeLimit(.minutes(1)))
    func initialNavigationSeesAppearanceBeforeAnyHostIsAttached() async throws {
        let html = Data("""
            <!doctype html><html><head><script>
            window.initialTheme = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
            </script></head><body id="initial-theme-fixture">Theme</body></html>
            """.utf8)
        let response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.count)\r\nConnection: close\r\n\r\n".utf8) + html
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let isReady = LockIsolated(false)
        listener.stateUpdateHandler = { state in
            if case .ready = state { isReady.withValue { $0 = true } }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, _ in
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .global())
        defer { listener.cancel() }
        try await eventually { isReady.value }
        let port = try #require(listener.port)
        try #require(port.rawValue != 0)
        let bookmark = BrowserBookmark(
            id: UUID(), title: "Initial theme", url: try #require(URL(string: "http://127.0.0.1:\(port.rawValue)/"))
        )
        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        let pool = BrowserWebViewPool(initialAppearance: { darkAppearance })
        defer { pool.discard(bookmark.id) }
        // Unlike the host test, activate itself starts the fixture's first navigation.
        pool.activate(bookmark)
        let webView = try #require(pool.webViews[bookmark.id])
        #expect(webView.superview == nil)
        try await eventually {
            (try? await evaluate("document.body?.id", in: webView)) == "initial-theme-fixture"
        }
        #expect(try await evaluate("window.initialTheme", in: webView) == "dark")
        #expect(webView.superview == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func hostAppearanceUpdatesTheWebsitesColorSchemeWithoutReloading() async throws {
        let pool = BrowserWebViewPool()
        let bookmark = BrowserBookmark(
            id: UUID(), title: "Offline theme", url: try #require(URL(string: "about:blank"))
        )
        pool.activate(bookmark)
        let webView = try #require(pool.webViews[bookmark.id])
        // The fixture is local HTML; navigation policy and network availability are outside this test.
        webView.navigationDelegate = nil
        let hostingView = NSHostingView(rootView: BrowserWebViewHost(pool: pool, bookmarkID: bookmark.id)
            .environment(\.colorScheme, .dark))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 375, height: 667),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer {
            window.close()
            pool.discard(bookmark.id)
        }
        hostingView.layoutSubtreeIfNeeded()
        webView.loadHTMLString("""
            <!doctype html><html><head><style>
            :root { color-scheme: light dark; }
            body { background: rgb(255, 255, 255); }
            @media (prefers-color-scheme: dark) { body { background: rgb(17, 17, 17); } }
            </style></head><body id="theme-fixture">Theme</body></html>
            """, baseURL: nil)
        try await eventually {
            guard webView.appearance?.name == .darkAqua else { return false }
            return (try? await evaluate("document.body?.id", in: webView)) == "theme-fixture"
        }
        try await eventually {
            (try? await evaluate("String(matchMedia('(prefers-color-scheme: dark)').matches)", in: webView)) == "true"
        }
        #expect(try await evaluate("getComputedStyle(document.body).backgroundColor", in: webView) == "rgb(17, 17, 17)")
        #expect(try await evaluate("document.querySelector('meta[name=viewport]')?.content", in: webView) == "width=device-width, initial-scale=1")
        _ = try await evaluate("window.onlySwitchThemeProbe = 'preserved'", in: webView)

        hostingView.rootView = BrowserWebViewHost(pool: pool, bookmarkID: bookmark.id)
            .environment(\.colorScheme, .light)
        hostingView.layoutSubtreeIfNeeded()
        try await eventually {
            guard webView.appearance?.name == .aqua else { return false }
            return (try? await evaluate("String(matchMedia('(prefers-color-scheme: dark)').matches)", in: webView)) == "false"
        }
        #expect(try await evaluate("getComputedStyle(document.body).backgroundColor", in: webView) == "rgb(255, 255, 255)")
        #expect(try await evaluate("window.onlySwitchThemeProbe", in: webView) == "preserved")
        #expect(pool.webViews[bookmark.id] === webView)
    }

    @Test(arguments: [false, true])
    func everyBookmarkUsesMobileSafariRegardlessOfLegacyPreference(_ legacyMobile: Bool) throws {
        let pool = BrowserWebViewPool()
        let bookmark = BrowserBookmark(
            id: UUID(), title: "Offline", url: try #require(URL(string: "about:blank")),
            usesMobileUserAgent: legacyMobile
        )
        defer { pool.discard(bookmark.id) }
        pool.activate(bookmark)
        let webView = try #require(pool.webViews[bookmark.id])
        #expect(webView.customUserAgent == BrowserUserAgent.mobile)
        pool.setMobileUserAgent(bookmark.id, false)
        #expect(webView.customUserAgent == BrowserUserAgent.mobile)
        pool.activate(bookmark)
        #expect(pool.webViews[bookmark.id] === webView)
        #expect(webView.customUserAgent == BrowserUserAgent.mobile)
    }

    private func evaluate(_ script: String, in webView: WKWebView, world: WKContentWorld = .page) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script, in: nil, in: world) { result in
                switch result {
                case let .success(value):
                    continuation.resume(returning: value as? String ?? "")
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func eventually(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ThemeTestFailure.conditionTimedOut
    }

    private enum ThemeTestFailure: Error {
        case conditionTimedOut
    }
}
#endif
