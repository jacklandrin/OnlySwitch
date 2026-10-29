#if os(macOS)
import AppKit
import Combine
import ComposableArchitecture
import Extensions
import SwiftUI

/// Hosts one `ScreenshotEditorView` per screenshot. Each window owns its own editor store; closing the window
/// is the same as Cancel. `onFinished` receives the library's updated items after a save, or nil.
@MainActor
public enum ScreenshotEditorWindow {
    private static var controllers: [UUID: ScreenshotEditorWindowController] = [:]

    public static func present(itemID: UUID, onFinished: @escaping @MainActor ([ScreenshotItem]?) -> Void) {
        if let existing = controllers[itemID] {
            existing.focus()
            return
        }
        let controller = ScreenshotEditorWindowController(itemID: itemID) { items in
            controllers[itemID] = nil
            onFinished(items)
        }
        controllers[itemID] = controller
        controller.focus()
    }
}

/// Relays the editor's `.delegate(.finished)` from the store's effect back to the window controller.
@MainActor
private final class ScreenshotEditorFinisher {
    var handler: (([ScreenshotItem]?) -> Void)?
    func finish(_ items: [ScreenshotItem]?) { handler?(items) }
}

@MainActor
private final class ScreenshotEditorWindowController: NSWindowController, NSWindowDelegate {
    private static let minimumSize = NSSize(width: 520, height: 380)
    /// Toolbar, padding and spacing around the image.
    private static let chrome = NSSize(width: 24, height: 88)

    private let store: StoreOf<ScreenshotEditorFeature>
    private let onFinished: @MainActor ([ScreenshotItem]?) -> Void
    private var sizeObservation: AnyCancellable?
    private var isFinished = false
    private var isClosing = false

    init(itemID: UUID, onFinished: @escaping @MainActor ([ScreenshotItem]?) -> Void) {
        let finisher = ScreenshotEditorFinisher()
        store = Store(initialState: ScreenshotEditorFeature.State(itemID: itemID)) {
            ScreenshotEditorFeature()
            Reduce<ScreenshotEditorFeature.State, ScreenshotEditorFeature.Action> { _, action in
                guard case let .delegate(.finished(items)) = action else { return .none }
                return .run { _ in await finisher.finish(items) }
            }
        }
        self.onFinished = onFinished
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.fit(NSSize(width: 960, height: 640), on: NSScreen.main)),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit Screenshot".localized()
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = Self.minimumSize
        window.contentViewController = NSHostingController(rootView: ScreenshotEditorView(store: store))
        window.setContentSize(Self.fit(NSSize(width: 960, height: 640), on: NSScreen.main))
        window.center()
        super.init(window: window)
        window.delegate = self
        finisher.handler = { [weak self] items in self?.finish(items) }
        // Resize once to the image's size (in points) when it has loaded.
        sizeObservation = store.publisher.document.pixelSize
            .removeDuplicates()
            .first { $0.width > 0 && $0.height > 0 }
            .sink { [weak self] size in self?.resize(toPixelSize: size) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func focus() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { !store.isSaving }

    func windowWillClose(_ notification: Notification) {
        isClosing = true
        // Closing the window is Cancel; the delegate action then finishes the session.
        if !isFinished { store.send(.cancelTapped) }
    }

    private func finish(_ items: [ScreenshotItem]?) {
        guard !isFinished else { return }
        isFinished = true
        sizeObservation = nil
        if !isClosing { window?.close() }
        onFinished(items)
    }

    private func resize(toPixelSize pixelSize: CGSize) {
        guard let window else { return }
        let scale = window.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let content = NSSize(width: pixelSize.width / scale + Self.chrome.width, height: pixelSize.height / scale + Self.chrome.height)
        window.setContentSize(Self.fit(content, on: window.screen ?? NSScreen.main))
        window.center()
    }

    /// Fits `size` within 80% of the screen's visible frame, never below the minimum size.
    private static func fit(_ size: NSSize, on screen: NSScreen?) -> NSSize {
        let visible = screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let maxWidth = max(minimumSize.width, visible.width * 0.8), maxHeight = max(minimumSize.height, visible.height * 0.8)
        return NSSize(width: min(max(size.width, minimumSize.width), maxWidth), height: min(max(size.height, minimumSize.height), maxHeight))
    }
}
#endif
