import AppKit
import SwiftUI

@MainActor
public final class DesktopPetController: NSObject {
    public private(set) var isVisible = false
    public var isControlPresented: Bool {
        presentation.isControlPresented
    }
    public var windowNumber: Int {
        panel.windowNumber
    }

    private static let autosaveName = "OnlySwitchDesktopPetWindow"

    private let onActivate: @MainActor () -> Void
    private let panel: DesktopPetPanel
    private let presentation = DesktopPetPresentation()
    private var dragStartOrigin: CGPoint?
    private var dragStartMouseLocation: CGPoint?
    private var restoredFrame = false

    public init(onActivate: @escaping @MainActor () -> Void) {
        self.onActivate = onActivate
        panel = DesktopPetPanel(
            contentRect: CGRect(origin: .zero, size: DesktopPetMetrics.canvasSize),
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
        saveFrame()
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

    public func setControlPresented(_ isPresented: Bool) {
        presentation.isControlPresented = isPresented
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
            .ignoresCycle,
            .stationary
        ]
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

        if panel.setFrameUsingName(Self.autosaveName) {
            panel.setFrame(
                DesktopPetLayout.resizedFramePreservingCenter(
                    panel.frame,
                    to: DesktopPetMetrics.canvasSize
                ),
                display: false
            )
        } else if let screen = NSScreen.main ?? NSScreen.screens.first {
            panel.setFrame(
                DesktopPetLayout.defaultFrame(
                    size: DesktopPetMetrics.canvasSize,
                    visibleFrame: screen.visibleFrame,
                    horizontalInset: DesktopPetMetrics.defaultPanelInsets.width,
                    verticalInset: DesktopPetMetrics.defaultPanelInsets.height
                ),
                display: false
            )
        }
        panel.setFrameAutosaveName(Self.autosaveName)
    }

    private func dragChanged(_: DragGesture.Value) {
        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
            dragStartMouseLocation = NSEvent.mouseLocation
        }
        guard let dragStartOrigin, let dragStartMouseLocation else { return }

        let currentMouseLocation = NSEvent.mouseLocation
        let currentOrigin = DesktopPetInteraction.draggedOrigin(
            startOrigin: dragStartOrigin,
            startMouseLocation: dragStartMouseLocation,
            currentMouseLocation: currentMouseLocation
        )
        presentation.isDragging = !DesktopPetInteraction.isClick(
            translation: CGSize(
                width: currentOrigin.x - dragStartOrigin.x,
                height: currentOrigin.y - dragStartOrigin.y
            )
        )
        panel.setFrameOrigin(currentOrigin)
    }

    private func dragEnded(_: DragGesture.Value) {
        defer {
            dragStartOrigin = nil
            dragStartMouseLocation = nil
            presentation.isDragging = false
        }

        guard let dragStartOrigin, let dragStartMouseLocation else { return }
        let finalOrigin = DesktopPetInteraction.draggedOrigin(
            startOrigin: dragStartOrigin,
            startMouseLocation: dragStartMouseLocation,
            currentMouseLocation: NSEvent.mouseLocation
        )
        let translation = CGSize(
            width: finalOrigin.x - dragStartOrigin.x,
            height: finalOrigin.y - dragStartOrigin.y
        )

        if DesktopPetInteraction.isClick(translation: translation) {
            panel.setFrameOrigin(dragStartOrigin)
            onActivate()
        } else {
            panel.setFrameOrigin(finalOrigin)
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
