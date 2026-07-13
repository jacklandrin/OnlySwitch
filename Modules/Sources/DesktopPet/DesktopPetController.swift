import AppKit
import SwiftUI

@MainActor
public final class DesktopPetController: NSObject {
    public private(set) var isVisible = false

    private static let autosaveName = "OnlySwitchDesktopPetWindow"
    private static let panelSize = CGSize(width: 120, height: 130)

    private let onActivate: @MainActor () -> Void
    private let panel: DesktopPetPanel
    private let presentation = DesktopPetPresentation()
    private var dragStartOrigin: CGPoint?
    private var restoredFrame = false

    public init(onActivate: @escaping @MainActor () -> Void) {
        self.onActivate = onActivate
        panel = DesktopPetPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        configurePanel()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func show() {
        restoreFrameIfNeeded()
        constrainPanelToVisibleScreen()
        presentation.isActive = true
        isVisible = true
        panel.orderFrontRegardless()
    }

    public func hide() {
        saveFrame()
        presentation.isActive = false
        presentation.isDragging = false
        isVisible = false
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        panel.setFrameAutosaveName(Self.autosaveName)

        panel.contentView = NSHostingView(
            rootView: DesktopPetRootView(
                presentation: presentation,
                onDragChanged: { [weak self] value in
                    self?.dragChanged(value)
                },
                onDragEnded: { [weak self] value in
                    self?.dragEnded(value)
                }
            )
        )
    }

    private func restoreFrameIfNeeded() {
        guard !restoredFrame else { return }
        restoredFrame = true

        if !panel.setFrameUsingName(Self.autosaveName),
           let screen = NSScreen.main ?? NSScreen.screens.first {
            panel.setFrame(
                DesktopPetLayout.defaultFrame(
                    size: Self.panelSize,
                    visibleFrame: screen.visibleFrame
                ),
                display: false
            )
        }
    }

    private func dragChanged(_ value: DragGesture.Value) {
        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
        }
        guard let dragStartOrigin else { return }

        presentation.isDragging = !DesktopPetInteraction.isClick(
            translation: value.translation
        )
        panel.setFrameOrigin(
            CGPoint(
                x: dragStartOrigin.x + value.translation.width,
                y: dragStartOrigin.y - value.translation.height
            )
        )
    }

    private func dragEnded(_ value: DragGesture.Value) {
        defer {
            dragStartOrigin = nil
            presentation.isDragging = false
        }

        if DesktopPetInteraction.isClick(translation: value.translation) {
            if let dragStartOrigin {
                panel.setFrameOrigin(dragStartOrigin)
            }
            onActivate()
        } else {
            constrainPanelToVisibleScreen()
            saveFrame()
        }
    }

    @objc private func screenParametersDidChange() {
        constrainPanelToVisibleScreen()
        saveFrame()
    }

    private func constrainPanelToVisibleScreen() {
        let screens = NSScreen.screens
        guard let index = DesktopPetLayout.bestScreenIndex(
            for: panel.frame,
            visibleFrames: screens.map(\.visibleFrame)
        ) else { return }

        panel.setFrame(
            DesktopPetLayout.constrainedFrame(panel.frame, to: screens[index].visibleFrame),
            display: true
        )
    }

    private func saveFrame() {
        panel.saveFrame(usingName: Self.autosaveName)
    }
}
