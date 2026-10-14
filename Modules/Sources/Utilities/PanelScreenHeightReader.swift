#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// Reports usable content height after screen exclusions and native window insets.
public struct PanelScreenHeightReader: NSViewRepresentable {
    private let onChange: @MainActor (CGFloat) -> Void

    public init(onChange: @escaping @MainActor (CGFloat) -> Void) {
        self.onChange = onChange
    }

    public func makeNSView(context: Context) -> ScreenView {
        ScreenView(onChange: onChange)
    }

    public func updateNSView(_ view: ScreenView, context: Context) {
        view.onChange = onChange
    }

    @MainActor
    public final class ScreenView: NSView {
        var onChange: @MainActor (CGFloat) -> Void
        private var observations = Set<AnyCancellable>()
        private var lastHeight: CGFloat?

        init(onChange: @escaping @MainActor (CGFloat) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observations.removeAll()
            lastHeight = nil
            guard let window else { return }
            let center = NotificationCenter.default
            Publishers.Merge3(
                center.publisher(for: NSWindow.didChangeScreenNotification, object: window),
                center.publisher(for: NSApplication.didChangeScreenParametersNotification),
                center.publisher(for: NSWindow.didResizeNotification, object: window)
            )
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.reportHeight() }
            }
            .store(in: &observations)
            Task { @MainActor [weak self] in self?.reportHeight() }
        }

        private func reportHeight() {
            guard let window, let screenHeight = window.screen?.visibleFrame.height else { return }
            let height = AdaptivePanelHeightPolicy.availableContentHeight(
                screenHeight: screenHeight,
                windowHeight: window.frame.height,
                contentLayoutHeight: window.contentLayoutRect.height
            )
            guard
                  height.isFinite, height > 0, height != lastHeight else { return }
            lastHeight = height
            onChange(height)
        }
    }
}
#endif
