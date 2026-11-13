import AppKit
import SwiftUI
import WebKit

/// Shows the pooled web view for `bookmarkID`. The pool, not this view, owns the web view, so removing
/// the host (tab switch, popover close) leaves the page running.
public struct BrowserWebViewHost: NSViewRepresentable {
    @ObservedObject var pool: BrowserWebViewPool
    let bookmarkID: UUID

    public init(pool: BrowserWebViewPool, bookmarkID: UUID) {
        self.pool = pool
        self.bookmarkID = bookmarkID
    }

    public func makeNSView(context: Context) -> BrowserWebViewContainer {
        BrowserWebViewContainer()
    }

    public func updateNSView(_ container: BrowserWebViewContainer, context: Context) {
        container.display(pool.webViews[bookmarkID])
    }

    public static func dismantleNSView(_ container: BrowserWebViewContainer, coordinator: ()) {
        container.display(nil)
    }
}

public final class BrowserWebViewContainer: NSView {
    private weak var current: WKWebView?

    func display(_ webView: WKWebView?) {
        if current === webView, webView?.superview === self { return }
        if let current, current.superview === self { current.removeFromSuperview() }
        current = webView
        attach()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Another host (popover vs. Only Control) may have taken the web view while this one was hidden.
        if window != nil { attach() }
    }

    private func attach() {
        guard let current, current.superview !== self else { return }
        current.removeFromSuperview()
        current.frame = bounds
        current.autoresizingMask = [.width, .height]
        addSubview(current)
    }
}
