import Foundation
import Testing
@testable import WebBrowser

struct BrowserPageCacheTests {
    @Test func evictsLeastRecentlyUsedBeyondCapacity() {
        let (a, b, c, d) = (UUID(), UUID(), UUID(), UUID())
        var cache = BrowserPageCache(capacity: 3)
        #expect(cache.touch(a).isEmpty)
        #expect(cache.touch(b).isEmpty)
        #expect(cache.touch(c).isEmpty)
        #expect(cache.touch(a).isEmpty)
        #expect(cache.touch(d) == [b])
        #expect(cache.order == [c, a, d])
    }

    @Test func removeForgetsAPageAndCapacityHasAFloorOfOne() {
        let (a, b) = (UUID(), UUID())
        var cache = BrowserPageCache(capacity: 0)
        cache.touch(a)
        #expect(cache.touch(b) == [a])
        cache.remove(b)
        #expect(cache.order.isEmpty)
    }
}

struct BrowserNavigationPolicyTests {
    private func decide(_ string: String, mainFrame: Bool = true, user: Bool = true) -> BrowserNavigationDecision {
        BrowserNavigationPolicy.decision(for: URL(string: string), isMainFrame: mainFrame, isUserInitiated: user)
    }

    @Test func allowsWebSchemes() {
        #expect(decide("https://example.com") == .allow)
        #expect(decide("http://example.com") == .allow)
        #expect(decide("about:blank") == .allow)
        #expect(decide("blob:https://example.com/1") == .allow)
        #expect(decide("data:image/png;base64,AA", mainFrame: false) == .allow)
    }

    @Test func blocksTopLevelDataAndUnknownSchemes() {
        #expect(decide("data:text/html,hi") == .cancel)
        #expect(decide("file:///etc/passwd") == .cancel)
        #expect(decide("javascript:alert(1)") == .cancel)
        #expect(decide("x-apple-helpviewer://x") == .cancel)
        #expect(BrowserNavigationPolicy.decision(for: nil, isMainFrame: true, isUserInitiated: true) == .cancel)
    }

    @Test func handsContactSchemesToTheSystemOnlyOnUserClicks() {
        #expect(decide("mailto:a@example.com") == .openExternally)
        #expect(decide("tel:123") == .openExternally)
        #expect(decide("mailto:a@example.com", user: false) == .cancel)
    }
}
