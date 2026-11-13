import AppKit
import SwiftUI
import WebKit

/// Shows the pooled web view for `bookmarkID`. The pool, not this view, owns the web view, so removing
/// the host (tab switch, popover close) leaves the page running. It also reports whether the pointer
/// is where the auto-hiding toolbar should appear (see `BrowserToolbarReveal`).
public struct BrowserWebViewHost: NSViewRepresentable {
    @ObservedObject var pool: BrowserWebViewPool
    let bookmarkID: UUID
    var toolbarIsVisible = false
    var toolbarHeight: CGFloat = 0
    var onPointerWantsToolbarChange: @MainActor (Bool) -> Void = { _ in }

    public init(
        pool: BrowserWebViewPool,
        bookmarkID: UUID,
        toolbarIsVisible: Bool = false,
        toolbarHeight: CGFloat = 0,
        onPointerWantsToolbarChange: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.pool = pool
        self.bookmarkID = bookmarkID
        self.toolbarIsVisible = toolbarIsVisible
        self.toolbarHeight = toolbarHeight
        self.onPointerWantsToolbarChange = onPointerWantsToolbarChange
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> BrowserWebViewContainer {
        let container = BrowserWebViewContainer()
        let coordinator = context.coordinator
        container.onPointerMove = { [weak coordinator] distance in coordinator?.pointerMoved(distanceFromTop: distance) }
        return container
    }

    public func updateNSView(_ container: BrowserWebViewContainer, context: Context) {
        context.coordinator.toolbarIsVisible = toolbarIsVisible
        context.coordinator.toolbarHeight = toolbarHeight
        context.coordinator.onChange = onPointerWantsToolbarChange
        container.display(pool.webViews[bookmarkID])
    }

    public static func dismantleNSView(_ container: BrowserWebViewContainer, coordinator: Coordinator) {
        container.onPointerMove = nil
        container.display(nil)
    }

    /// Turns raw pointer movement into change-only toolbar requests, so SwiftUI state is not touched per move.
    @MainActor
    public final class Coordinator {
        var toolbarIsVisible = false
        var toolbarHeight: CGFloat = 0
        var onChange: @MainActor (Bool) -> Void = { _ in }
        private var lastRequest = false

        func pointerMoved(distanceFromTop: CGFloat?) {
            let wants = BrowserToolbarReveal.pointerWantsToolbar(
                distanceFromTop: distanceFromTop,
                toolbarIsVisible: toolbarIsVisible,
                toolbarHeight: toolbarHeight
            )
            guard wants != lastRequest else { return }
            lastRequest = wants
            onChange(wants)
        }
    }
}

public final class BrowserWebViewContainer: NSView {
    private weak var current: WKWebView?
    private var trackingArea: NSTrackingArea?
    /// Pointer distance from the top edge, or `nil` when it leaves the view.
    var onPointerMove: ((CGFloat?) -> Void)?

    func display(_ webView: WKWebView?) {
        if current === webView, webView?.superview === self { return }
        if let current, current.superview === self { current.removeFromSuperview() }
        current = webView
        attach()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Another host (popover vs. Only Control) may have taken the web view while this one was hidden.
        if window != nil { attach() } else { onPointerMove?(nil) }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // Owned by the container, so it reports movement even while the web view (or the SwiftUI toolbar
        // floating above it) handles the mouse.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        reportPointer(event)
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        reportPointer(event)
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointerMove?(nil)
    }

    private func reportPointer(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onPointerMove?(isFlipped ? point.y : bounds.height - point.y)
    }

    private func attach() {
        guard let current, current.superview !== self else { return }
        current.removeFromSuperview()
        current.frame = bounds
        current.autoresizingMask = [.width, .height]
        addSubview(current)
    }
}
