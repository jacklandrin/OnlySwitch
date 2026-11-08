import AppKit
import ComposableArchitecture
import Extensions
import Observation
import SwiftUI

struct DockPreviewScreenFrame: Equatable, Sendable {
    let frame: CGRect
    let visibleFrame: CGRect
}

@MainActor
final class DockPreviewPanelController {
    private let store: StoreOf<DockPreviewFeature>
    private let panel: DockPreviewPanel
    private let updatePreviewFrame: @MainActor (CGRect?) -> Void
    private var isObserving = false

    init(
        store: StoreOf<DockPreviewFeature>,
        updatePreviewFrame: @escaping @MainActor (CGRect?) -> Void
    ) {
        self.store = store
        self.updatePreviewFrame = updatePreviewFrame
        panel = DockPreviewPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        if #available(macOS 26.0, *) {
            // Glass supplies its own depth; a window shadow adds an offset contour.
            panel.hasShadow = false
        } else {
            panel.hasShadow = true
        }
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: DockPreviewView(store: store))
    }

    func start() {
        guard !isObserving else { return }
        isObserving = true
        render()
    }

    func stop() {
        isObserving = false
        panel.orderOut(nil)
        updatePreviewFrame(nil)
    }

    private func render() {
        guard isObserving else { return }
        let (preview, status, showPermissionHelp) = withObservationTracking {
            (store.preview, store.status, store.showPermissionHelp)
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }

        if showPermissionHelp {
            store.send(.permissionHelpPresented)
            panel.orderOut(nil)
            updatePreviewFrame(nil)
            let alert = NSAlert()
            alert.messageText = "Dock Preview".localized()
            alert.informativeText = "Dock Preview requires Accessibility and Screen Recording permissions.".localized()
            alert.addButton(withTitle: "Open System Settings".localized())
            alert.addButton(withTitle: "Cancel".localized())
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            }
        }

        guard let preview,
              !preview.windows.isEmpty || status == .captureFailed || preview.mediaPlayer != nil else {
            panel.orderOut(nil)
            updatePreviewFrame(nil)
            return
        }

        let size = Self.size(for: preview, status: status)
        let frame = Self.frame(
            size: size,
            item: preview.itemFrame,
            visibleScreen: Self.currentVisibleScreen(
                for: preview.itemFrame,
                fallback: preview.screenFrame
            )
        )
        // Keep glass rendering away from the transparent window's backing edge.
        let inset = DockPreviewView.renderingInset
        panel.setFrame(frame.insetBy(dx: -inset, dy: -inset), display: true)
        updatePreviewFrame(frame)
        panel.makeKeyAndOrderFront(nil)
    }

    static func size(
        for preview: DockPreviewFeature.State.Preview,
        status: DockPreviewFeature.State.Status
    ) -> CGSize {
        let hasMedia = preview.mediaPlayer != nil
        guard !preview.windows.isEmpty else {
            guard status == .captureFailed else { return CGSize(width: 240, height: 52) }
            return CGSize(width: 240, height: hasMedia ? 52 + DockPreviewView.mediaControlsHeight : 52)
        }
        let width = min(CGFloat(preview.windows.count) * 190 + 24, 784)
        var height: CGFloat = status == .activationFailed ? 190 : 164
        if hasMedia { height += DockPreviewView.mediaControlsHeight }
        return CGSize(width: width, height: height)
    }

    static func frame(size: CGSize, item: CGRect, visibleScreen: CGRect) -> CGRect {
        let size = CGSize(
            width: min(size.width, visibleScreen.width),
            height: min(size.height, visibleScreen.height)
        )
        let gap: CGFloat = 8
        let bottomDistance = abs(item.midY - visibleScreen.minY)
        let leftDistance = abs(item.midX - visibleScreen.minX)
        let rightDistance = abs(item.midX - visibleScreen.maxX)
        let isLeftDock = item.maxX <= visibleScreen.minX ||
            (leftDistance < bottomDistance && leftDistance < rightDistance)
        let isRightDock = item.minX >= visibleScreen.maxX ||
            (rightDistance < bottomDistance && rightDistance < leftDistance)

        var origin: CGPoint
        if isLeftDock {
            origin = CGPoint(x: item.maxX + gap, y: item.midY - size.height / 2)
        } else if isRightDock {
            origin = CGPoint(x: item.minX - size.width - gap, y: item.midY - size.height / 2)
        } else {
            origin = CGPoint(x: item.midX - size.width / 2, y: item.maxY + gap)
        }

        origin.x = min(max(origin.x, visibleScreen.minX), visibleScreen.maxX - size.width)
        origin.y = min(max(origin.y, visibleScreen.minY), visibleScreen.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }

    static func currentVisibleScreen(for item: CGRect, fallback: CGRect) -> CGRect {
        resolvedVisibleScreen(
            for: item,
            fallback: fallback,
            screens: NSScreen.screens.map {
                DockPreviewScreenFrame(frame: $0.frame, visibleFrame: $0.visibleFrame)
            }
        )
    }

    static func resolvedVisibleScreen(
        for item: CGRect,
        fallback: CGRect,
        screens: [DockPreviewScreenFrame]
    ) -> CGRect {
        let itemCenter = CGPoint(x: item.midX, y: item.midY)
        return screens.first(where: { $0.frame.contains(itemCenter) })?.visibleFrame ?? fallback
    }
}

private final class DockPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
