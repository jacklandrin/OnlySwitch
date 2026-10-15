import AppKit
import SwiftUI
import WebKit

@main
@MainActor
enum AphroditeFittedPreviewHarness {
    static func main() throws {
        guard #available(macOS 26.0, *) else { print("SKIP: Aphrodite requires macOS 26"); return }
        _ = NSApplication.shared
        let app = AphroditeApp(id: UUID(), html: """
        <!doctype html><html><body style="margin:0;padding:10px"><button id="target" style="position:absolute;left:900px;top:800px;width:100px;height:50px" onclick="document.getElementById('wide').style.height='1100px'">Tap</button><div id="wide" style="width:1048px;height:900px"></div></body></html>
        """)
        let host = NSHostingView(rootView: AphroditeFittedPreview(app: app))
        host.frame = CGRect(x: 0, y: 0, width: 340, height: 500)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host; window.orderFront(nil)
        defer { window.close() }

        var webView: WKWebView?
        pump { webView = firstWebView(in: host); return (webView?.frame.width ?? 0) >= 1_068 && (webView?.frame.height ?? 0) >= 920 }
        guard let webView else { throw Failure("production fitted preview did not create its WebKit view") }
        try assertFits(webView, in: host)
        let firstLogical = webView.frame.size
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard webView.frame.size == firstLogical else { throw Failure("production logical canvas oscillated") }

        host.setFrameSize(CGSize(width: 500, height: 400)); window.setContentSize(host.frame.size); host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        guard webView.frame.size == firstLogical else { throw Failure("pane resize changed the unscaled logical canvas") }
        try assertFits(webView, in: host)

        let logicalPoint = CGPoint(x: 950, y: webView.isFlipped ? 825 : webView.bounds.height - 825)
        let hostPoint = webView.convert(logicalPoint, to: host)
        let windowPoint = host.convert(hostPoint, to: nil)
        guard let hit = window.contentView?.hitTest(windowPoint), hit === webView || hit.isDescendant(of: webView) else {
            throw Failure("scaled target does not hit the production WebKit view; flipped=\(webView.isFlipped), point=\(windowPoint), hit=\(String(describing: window.contentView?.hitTest(windowPoint)))")
        }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) { window.sendEvent(event) }
        }
        pump { webView.frame.height >= 1_120 }
        guard webView.frame.height >= 1_120 else { throw Failure("scaled click did not reach the generated button") }
        try assertFits(webView, in: host)
        print("PASS: production fitted preview preserves its logical canvas, refits without oscillation, and transforms hit testing")
    }

    private static func assertFits(_ webView: WKWebView, in host: NSView) throws {
        let displayed = webView.convert(webView.bounds, to: host)
        guard displayed.width <= host.bounds.width + 1, displayed.height <= host.bounds.height + 1,
              displayed.minX >= -1, displayed.minY >= -1 else { throw Failure("displayed WebKit bounds do not fit the pane: \(displayed) in \(host.bounds)") }
    }
    private static func firstWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        return view.subviews.lazy.compactMap(firstWebView).first
    }
    private static func pump(_ complete: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !complete(), Date() < deadline { RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.01))) }
    }
    private struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }
}
