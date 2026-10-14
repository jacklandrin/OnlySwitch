import AppKit
import WebKit

/// Runs outside xctest so WebKit can launch its normal macOS content process.
@main
@MainActor
struct AphroditeWebHeightHarness {
    static func main() throws {
        guard #available(macOS 26.0, *) else {
            print("SKIP: Aphrodite requires macOS 26")
            return
        }
        try run()
    }

    @available(macOS 26.0, *)
    private static func run() throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 1), configuration: configuration)
        var heights: [CGFloat] = []
        let coordinator = SecureAphroditeWebView.Coordinator { height in
            heights.append(height)
            view.setFrameSize(CGSize(width: 320, height: height))
            let commands = ["grow", "shrink", "clear", "oversize"]
            if heights.count <= commands.count {
                view.evaluateJavaScript("document.querySelector('iframe').contentWindow.postMessage('\(commands[heights.count - 1])', '*')", completionHandler: nil)
            }
        }
        coordinator.installReporter(in: view.configuration.userContentController)
        coordinator.beginNavigation(in: view.configuration.userContentController)
        view.navigationDelegate = coordinator

        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 320, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer {
            view.stopLoading()
            coordinator.teardown(view.configuration.userContentController)
            window.close()
        }

        let html = """
        <!doctype html><html><body style="margin:0"><div style="height:40px"></div><script>
        addEventListener('message', event => {
          if (event.data === 'grow') {
            const growth = document.createElement('div'); growth.id = 'growth'; growth.style.height = '640px';
            document.body.append(growth);
          } else if (event.data === 'shrink') document.getElementById('growth').remove();
          else if (event.data === 'clear') document.body.replaceChildren();
          else if (event.data === 'oversize') {
            const tall = document.createElement('div'); tall.style.height = '40000px'; document.body.append(tall);
          }
        });
        </script></body></html>
        """
        view.loadHTMLString(AphroditeSandboxDocument.make(from: html), baseURL: nil)
        pumpEvents(until: { heights.count >= 5 })
        guard heights == [40, 680, 40, 1, 20_000], view.frame.height == 20_000 else {
            throw Failure(message: "Expected content/viewport heights 40 → 680 → 40 → 1 → 20000; received \(heights)")
        }

        var isolated: Bool?
        view.evaluateJavaScript("""
        typeof window.webkit?.messageHandlers?.heightReporter === 'undefined'
        && document.querySelector('iframe').contentDocument === null
        && !document.querySelector('iframe').sandbox.contains('allow-same-origin')
        """) { result, _ in isolated = result as? Bool }
        pumpEvents(until: { isolated != nil })
        guard isolated == true else { throw Failure(message: "The generated app must retain its opaque sandbox and have no page-world height handler") }
        print("PASS: actual webview grows and shrinks 40 → 680 → 40 → 1; oversized content is bounded; sandbox and isolated handler verified")
    }

    private static func pumpEvents(until complete: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !complete(), Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.01)))
        }
    }

    private struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}
