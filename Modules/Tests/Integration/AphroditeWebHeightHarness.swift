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
        let firstID = UUID()
        let secondID = UUID()
        let testIDs = [firstID, secondID]
        removeStorage(for: testIDs)
        defer { removeStorage(for: testIDs) }
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
          } else if (event.data === 'store') {
            localStorage.setItem('counter', '41');
            parent.postMessage({type: 'aphrodite-test', value: localStorage.getItem('counter')}, '*');
          } else if (event.data === 'read') {
            parent.postMessage({type: 'aphrodite-test', value: localStorage.getItem('counter')}, '*');
          } else if (event.data === 'theme') {
            parent.postMessage({type: 'aphrodite-test', value: matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'}, '*');
          } else if (event.data === 'isolation') {
            let parentDocumentBlocked = false, parentWebKitBlocked = false;
            try { void parent.document; } catch { parentDocumentBlocked = true; }
            try { void parent.webkit; } catch { parentWebKitBlocked = true; }
            const reporterHidden = typeof window.webkit?.messageHandlers?.heightReporter === 'undefined';
            parent.postMessage({type: 'aphrodite-test', value: [parentDocumentBlocked, parentWebKitBlocked, reporterHidden].join(',')}, '*');
          } else if (event.data === 'restricted-storage') {
            let sessionStorageBlocked = false, indexedDBBlocked = false, indexedDBAliasBlocked = false;
            try { sessionStorage.setItem('forbidden', 'value'); } catch { sessionStorageBlocked = true; }
            try { indexedDB.open('forbidden'); } catch { indexedDBBlocked = true; }
            try { webkitIndexedDB.open('forbidden'); } catch { indexedDBAliasBlocked = true; }
            parent.postMessage({type: 'aphrodite-test', value: [sessionStorageBlocked, indexedDBBlocked, indexedDBAliasBlocked].join(',')}, '*');
          }
        });
        </script></body></html>
        """
        let firstApp = AphroditeApp(id: firstID, html: html)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let handler = AphroditeGeneratedDocumentSchemeHandler(app: firstApp)
        configuration.setURLSchemeHandler(handler, forURLScheme: AphroditeAppOrigin.scheme)
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
        coordinator.app = firstApp
        coordinator.schemeHandler = handler
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

        view.loadHTMLString(AphroditeSandboxDocument.make(origin: AphroditeAppOrigin(appID: firstID)), baseURL: AphroditeSandboxDocument.wrapperBaseURL)
        pumpEvents(until: { heights.count >= 5 })
        guard heights == [40, 680, 40, 1, 20_000], view.frame.height == 20_000 else {
            throw Failure(message: "Expected content/viewport heights 40 → 680 → 40 → 1 → 20000; received \(heights)")
        }

        guard try callChild("store", in: view) == "41",
              try callChild("isolation", in: view) == "true,true,true",
              try callChild("restricted-storage", in: view) == "true,true,true" else {
            throw Failure(message: "Generated content escaped its parent/native boundary or accessed a forbidden storage API")
        }
        window.appearance = NSAppearance(named: .aqua)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        guard try callChild("theme", in: view) == "light" else {
            throw Failure(message: "Generated content did not inherit the host Light appearance")
        }
        window.appearance = NSAppearance(named: .darkAqua)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        guard try callChild("theme", in: view) == "dark" else {
            throw Failure(message: "Generated content did not inherit the host Dark appearance")
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let sameOriginView = makeStorageView(app: firstApp)
        window.contentView = sameOriginView.view
        guard try callChild("read", in: sameOriginView.view) == "41" else {
            throw Failure(message: "localStorage did not persist after recreating the same app origin")
        }

        let secondApp = AphroditeApp(id: secondID, html: html)
        let secondOriginView = makeStorageView(app: secondApp)
        window.contentView = secondOriginView.view
        guard try callChild("read", in: secondOriginView.view) == nil else {
            throw Failure(message: "localStorage leaked between distinct app origins")
        }
        guard try callChild("store", in: secondOriginView.view) == "41" else {
            throw Failure(message: "Second origin could not store its isolated value")
        }

        let cleanup = AphroditeStorageCleanupOperation(origin: AphroditeAppOrigin(appID: firstID))
        var cleanupCompleted = false
        cleanup.start { cleanupCompleted = true }
        pumpEvents(until: { cleanupCompleted })
        let deletedOriginView = makeStorageView(app: firstApp)
        window.contentView = deletedOriginView.view
        guard try callChild("read", in: deletedOriginView.view) == nil else {
            throw Failure(message: "Deleted app origin retained localStorage")
        }
        window.contentView = secondOriginView.view
        guard try callChild("read", in: secondOriginView.view) == "41" else {
            throw Failure(message: "Deleting one app origin cleared another app's localStorage")
        }
        withExtendedLifetime([sameOriginView.coordinator, sameOriginView.handler, secondOriginView.coordinator, secondOriginView.handler, deletedOriginView.coordinator, deletedOriginView.handler]) {}
        print("PASS: actual webview sizing, Light/Dark matchMedia, persistent per-app localStorage, exact-origin deletion, blocked sessionStorage/IndexedDB, cross-origin parent isolation, and isolated handler verified")
    }

    private static func removeStorage(for appIDs: [UUID]) {
        let hosts = Set(appIDs.compactMap { AphroditeAppOrigin(appID: $0).indexURL.host })
        let dataStore = WKWebsiteDataStore.default()
        var completed = false
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let matchingRecords = records.filter { hosts.contains($0.displayName) }
            guard !matchingRecords.isEmpty else {
                completed = true
                return
            }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: matchingRecords) {
                completed = true
            }
        }
        pumpEvents(until: { completed })
    }

    @available(macOS 26.0, *)
    private static func makeStorageView(app: AphroditeApp) -> (view: WKWebView, coordinator: SecureAphroditeWebView.Coordinator, handler: AphroditeGeneratedDocumentSchemeHandler) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let handler = AphroditeGeneratedDocumentSchemeHandler(app: app)
        configuration.setURLSchemeHandler(handler, forURLScheme: AphroditeAppOrigin.scheme)
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 200), configuration: configuration)
        let coordinator = SecureAphroditeWebView.Coordinator { _ in }
        coordinator.app = app
        coordinator.schemeHandler = handler
        coordinator.installReporter(in: configuration.userContentController)
        coordinator.beginNavigation(in: configuration.userContentController)
        view.navigationDelegate = coordinator
        view.loadHTMLString(AphroditeSandboxDocument.make(origin: AphroditeAppOrigin(appID: app.id)), baseURL: AphroditeSandboxDocument.wrapperBaseURL)
        return (view, coordinator, handler)
    }

    @available(macOS 26.0, *)
    private static func callChild(_ command: String, in view: WKWebView) throws -> String? {
        let readinessDeadline = Date().addingTimeInterval(10)
        var hasFrame = false
        while !hasFrame, Date() < readinessDeadline {
            hasFrame = (try evaluate("document.querySelector('iframe')?.contentWindow != null", in: view) as? Bool) == true
            if !hasFrame { RunLoop.main.run(until: min(readinessDeadline, Date().addingTimeInterval(0.01))) }
        }
        guard hasFrame else { throw Failure(message: "Timed out waiting for generated-app frame") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        _ = try evaluate("""
        (() => {
          window.__aphroditeTestResult = '__pending__';
          const frame = document.querySelector('iframe');
          const receive = event => {
            if (event.source === frame.contentWindow && event.data?.type === 'aphrodite-test') {
              removeEventListener('message', receive);
              window.__aphroditeTestResult = event.data.value ?? '__null__';
            }
          };
          addEventListener('message', receive);
          frame.contentWindow.postMessage('\(command)', '*');
          return true;
        })()
        """, in: view)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let value = try evaluate("window.__aphroditeTestResult", in: view) as? String
            if value == "__null__" { return nil }
            if value != "__pending__" { return value }
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.01)))
        }
        throw Failure(message: "Timed out waiting for child command \(command)")
    }

    @available(macOS 26.0, *)
    private static func evaluate(_ source: String, in view: WKWebView) throws -> Any? {
        var completed = false
        var result: Any?
        var failure: Error?
        view.evaluateJavaScript(source) { value, error in
            result = value
            failure = error
            completed = true
        }
        pumpEvents(until: { completed })
        if let failure { throw failure }
        guard completed else { throw Failure(message: "Timed out evaluating harness JavaScript") }
        return result
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
