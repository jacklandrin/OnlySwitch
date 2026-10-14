#if os(macOS)
import AppKit
import Darwin
import SwiftUI

@MainActor
private final class ProbeState: ObservableObject {
    @Published var contentHeight: CGFloat = 10_000
    @Published var maximumContentHeight: CGFloat = 700
    weak var footerView: NSView?
    var panelSizeChanged: ((CGSize) -> Void)?
}

private struct FooterRecorder: NSViewRepresentable {
    let state: ProbeState
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        state.footerView = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { state.footerView = view }
}

private struct PopoverProbe: View {
    @ObservedObject var state: ProbeState
    private var panelHeight: CGFloat {
        AdaptivePanelHeightPolicy(minimumContentHeight: 1, chromeHeight: 32, maximumPanelHeight: state.maximumContentHeight)
            .panelHeight(for: state.contentHeight)
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView { Color.clear.frame(height: state.contentHeight) }
                .frame(height: max(0, panelHeight - 32))
            FooterRecorder(state: state).frame(height: 32)
        }
        .background(PanelScreenHeightReader { state.maximumContentHeight = $0 })
        .frame(width: 200, height: panelHeight)
        .onChange(of: panelHeight) { state.panelSizeChanged?(CGSize(width: 200, height: $0)) }
        .onAppear { state.panelSizeChanged?(CGSize(width: 200, height: panelHeight)) }
    }
}

@main
@MainActor
enum PopoverLayoutHarness {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await runFixture()
                application.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
                exit(1)
            }
        }
        application.run()
    }

    private static func runFixture() async throws {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        guard let button = statusItem.button else { throw Failure("missing status item button") }
        button.title = "•"
        try await waitUntil({
            guard let window = button.window, let screen = window.screen else { return false }
            return window.isVisible && window.frame.intersects(screen.frame)
                && button.visibleRect.width > 0 && button.visibleRect.height > 0
        }, diagnostics: { "status item is not positioned on screen" })

        let state = ProbeState()
        let popover = NSPopover()
        defer { popover.close() }
        popover.animates = false
        popover.behavior = .applicationDefined
        popover.contentViewController = NSHostingController(rootView: PopoverProbe(state: state))
        state.panelSizeChanged = { [weak popover] size in
            guard let popover, popover.contentSize != size else { return }
            popover.contentSize = size
        }
        popover.contentSize = CGSize(width: 200, height: state.maximumContentHeight)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover.contentViewController?.view.layoutSubtreeIfNeeded()

        try await waitUntil({ validate(popover: popover, state: state, expectsShort: false) }, diagnostics: { describe(popover: popover, state: state) })
        guard let longWindow = popover.contentViewController?.view.window else { throw Failure("missing long popover window") }
        let longHeight = longWindow.frame.height

        state.contentHeight = 40
        try await waitUntil({ validate(popover: popover, state: state, expectsShort: true) }, diagnostics: { describe(popover: popover, state: state) })
        guard let shortWindow = popover.contentViewController?.view.window, shortWindow.frame.height < longHeight else {
            throw Failure("short content did not shrink the native popover")
        }
        print("PASS long=\(longHeight) short=\(shortWindow.frame.height)")
    }

    private static func validate(popover: NSPopover, state: ProbeState, expectsShort: Bool) -> Bool {
        guard let window = popover.contentViewController?.view.window, let screen = window.screen,
              let footer = state.footerView, let footerWindow = footer.window else { return false }
        let visible = screen.visibleFrame
        let footerRect = footer.convert(footer.bounds, to: nil)
        let footerScreen = footerWindow.convertToScreen(footerRect)
        let windowFits = window.frame.height <= visible.height + 0.5 && window.frame.minY >= visible.minY - 1
        guard let host = popover.contentViewController?.view else { return false }
        let hostRect = host.convert(host.bounds, to: nil)
        let footerFitsContent = hostRect.contains(footerRect)
        let footerFitsScreen = footerScreen.minY >= visible.minY - 1 && footerScreen.maxY <= screen.frame.maxY + 4
        let expectedCap = AdaptivePanelHeightPolicy.availableContentHeight(
            screenHeight: visible.height,
            windowHeight: window.frame.height,
            contentLayoutHeight: window.contentLayoutRect.height
        )
        let capSettled = abs(state.maximumContentHeight - expectedCap) <= 1
        let fillsLongScreen = expectsShort || abs(window.frame.height - visible.height) <= 1
        return windowFits && footerFitsContent && footerFitsScreen && capSettled && fillsLongScreen && (!expectsShort || window.frame.height < 200)
    }

    private static func describe(popover: NSPopover, state: ProbeState) -> String {
        guard let window = popover.contentViewController?.view.window else {
            return "missing window; shown=\(popover.isShown) size=\(popover.contentSize) host=\(String(describing: popover.contentViewController?.view.frame))"
        }
        guard let footer = state.footerView else {
            return "missing footer; window=\(window.frame) host=\(String(describing: popover.contentViewController?.view.frame)) max=\(state.maximumContentHeight) subviews=\(String(describing: popover.contentViewController?.view.subviews))"
        }
        return "window=\(window.frame) content=\(window.contentLayoutRect) host=\(popover.contentViewController!.view.bounds) footer=\(footer.frame) max=\(state.maximumContentHeight)"
    }

    private static func waitUntil(_ predicate: () -> Bool, diagnostics: () -> String) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure("popover geometry did not reach the expected state: \(diagnostics())")
    }

    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
#endif
