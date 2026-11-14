import AppKit
import DesktopPetSkinKit
import SwiftUI
import ComposableArchitecture

@MainActor
public final class DesktopPetController: NSObject {
    public private(set) var isVisible = false
    public private(set) var pomodoroState: DesktopPetPomodoroState?
    public var isControlPresented: Bool {
        presentation.isControlPresented
    }
    public var contentSize: CGSize {
        panel.frame.size
    }
    public var windowNumber: Int {
        panel.windowNumber
    }

    private static let autosaveName = "OnlySwitchDesktopPetWindow"

    private let onActivate: @MainActor () -> Void
    private let onClose: @MainActor () -> Void
    let panel: DesktopPetPanel
    let playbackStore: StoreOf<DesktopPetPlaybackFeature>
    let activityStore: StoreOf<DesktopPetAgentActivityFeature>
    let needsStore: StoreOf<DesktopPetNeedsFeature>
    let presentation = DesktopPetPresentation()
    var dragStartOrigin: CGPoint?
    private var dragStartMouseLocation: CGPoint?
    private var restoredFrame = false
    var dock: Dock?
    var mouseMonitors: [Any] = []
    var pendingPhaseTask: Task<Void, Never>?
    var edgeSpring: DesktopPetSpring?
    var edgeDisplayLink: CADisplayLink?

    /// A pet pushed against a screen edge, which hides behind it until the mouse comes near that edge.
    struct Dock {
        var edge: DesktopPetDockEdge
        var screenFrame: CGRect
        var restingFrame: CGRect
        var phase = DesktopPetEdgePhase.revealed

        var frame: CGRect {
            DesktopPetEdgeDocking.frame(for: phase, restingFrame: restingFrame, edge: edge, screenFrame: screenFrame)
        }
    }

    /// The on-screen frame, even while the pet is hidden behind a screen edge.
    var restingFrame: CGRect {
        dock?.restingFrame ?? panel.frame
    }

    public init(
        onActivate: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void = {},
        playbackClient: DesktopPetPlaybackClient = .init(),
        activityClient: DesktopPetAgentActivityClient = .liveValue,
        needsStorage: DesktopPetNeedsStorage = .liveValue
    ) {
        playbackStore = Store(initialState: DesktopPetPlaybackFeature.State()) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playbackClient
        }
        activityStore = Store(initialState: DesktopPetAgentActivityFeature.State()) {
            DesktopPetAgentActivityFeature()
        } withDependencies: {
            $0.desktopPetAgentActivity = activityClient
        }
        needsStore = Store(initialState: DesktopPetNeedsFeature.State()) {
            DesktopPetNeedsFeature()
        } withDependencies: {
            $0.desktopPetNeedsStorage = needsStorage
        }
        self.onActivate = onActivate
        self.onClose = onClose
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
        activityStore.send(.stop)
        needsStore.send(.stop)
        stopEdgeTracking()
    }

    public func show() {
        restoreFrameIfNeeded()
        resizeContent(display: false)
        constrainPanelToVisibleScreen()
        saveFrame()
        presentation.isActive = true
        isVisible = true
        activityStore.send(.start)
        needsStore.send(.start)
        panel.orderFrontRegardless()
        updateEdgeTracking()
    }

    public func hide() {
        activityStore.send(.stop)
        needsStore.send(.stop)
        clearPlayback()
        stopEdgeTracking()
        if var dock, dock.phase != .revealed {
            dock.phase = .revealed
            self.dock = dock
            presentation.edgeTilt = 0
            panel.setFrame(dock.restingFrame, display: false)
        }
        saveFrame()
        presentation.isActive = false
        presentation.isDragging = false
        isVisible = false
        panel.orderOut(nil)
    }

    public func refreshPlayback() {
        guard isVisible else { return }
        playbackStore.send(.refresh)
    }

    public func clearPlayback() {
        playbackStore.send(.clear)
    }

    private func resizeContent(display: Bool? = nil) {
        let size = DesktopPetMetrics.canvasSize(
            for: pomodoroState, showsPlayback: playbackStore.source != nil,
            showsAgentStatus: activityStore.showsStatus
        )
        var frame = DesktopPetLayout.resizedFramePreservingPet(restingFrame, to: size)
        switch dock?.edge {
        case .left: frame.origin.x = restingFrame.minX
        case .right: frame.origin.x = restingFrame.maxX - size.width
        case nil: break
        }
        setRestingFrame(frame, display: display ?? isVisible)
        constrainPanelToVisibleScreen()
        saveFrame()
    }

    /// Re-reads the hunger setting after Settings changes it.
    public func reloadNeedsSettings() {
        needsStore.send(.settingsChanged)
        updateEdgeVisibility()
    }

    public func setControlPresented(_ isPresented: Bool) {
        presentation.isControlPresented = isPresented
        updateEdgeVisibility()
    }

    /// Shows a custom skin, or the built-in pet for `nil`. A web view exists only while a skin is set.
    public func setSkin(_ skin: DesktopPetSkin?) {
        guard presentation.skin != skin else { return }
        presentation.skin = skin
    }

    public func setPomodoroState(_ state: DesktopPetPomodoroState?) {
        guard pomodoroState != state else { return }

        pomodoroState = state
        presentation.pomodoroState = state
        resizeContent()
    }

    func close() {
        onClose()
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
                },
                playbackStore: playbackStore,
                activityStore: activityStore,
                needsStore: needsStore,
                onPlaybackVisibilityChanged: { [weak self] _ in
                    self?.resizeContent()
                },
                onActivityVisibilityChanged: { [weak self] in
                    self?.resizeContent()
                    self?.updateEdgeTracking()
                },
                onNeedsChanged: { [weak self] in
                    self?.updateEdgeVisibility()
                },
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )
    }

    private func restoreFrameIfNeeded() {
        guard !restoredFrame else { return }
        restoredFrame = true

        if panel.setFrameUsingName(Self.autosaveName) {
            panel.setFrame(
                DesktopPetLayout.restoredFramePreservingPet(
                    panel.frame,
                    to: DesktopPetMetrics.canvasSize
                ),
                display: false
            )
        } else if let screen = NSScreen.main ?? NSScreen.screens.first {
            panel.setFrame(
                DesktopPetLayout.defaultFrame(
                    size: DesktopPetMetrics.canvasSize,
                    visibleFrame: screen.visibleFrame
                ),
                display: false
            )
        }
        panel.setFrameAutosaveName(Self.autosaveName)
    }

    private func dragChanged(_: DragGesture.Value) {
        cancelPendingPhase()
        stopEdgeSpring()
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
        if presentation.isDragging, dock != nil {
            dock = nil
            presentation.edgeTilt = 0
            presentation.isActive = true
        }
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
        updateEdgeTracking()
    }

    @objc private func screenParametersDidChange() {
        constrainPanelToVisibleScreen()
        saveFrame()
        updateEdgeTracking()
    }

    func constrainPanelToVisibleScreen() {
        let screens = NSScreen.screens
        guard let index = DesktopPetLayout.bestScreenIndex(
            for: restingFrame,
            visibleFrames: screens.map(\.visibleFrame)
        ) else { return }

        let screen = screens[index]
        let frame = DesktopPetLayout.constrainedFrame(restingFrame, to: screen.visibleFrame)
        let edge = DesktopPetEdgeDocking.dockEdge(
            for: frame,
            visibleFrame: screen.visibleFrame,
            screenFrame: screen.frame,
            screenFrames: screens.map(\.frame)
        )
        let previousPhase = dock?.phase ?? .revealed
        if let edge {
            let phase = dock?.edge == edge ? previousPhase : .revealed
            dock = Dock(edge: edge, screenFrame: screen.frame, restingFrame: frame, phase: phase)
        } else {
            dock = nil
        }
        if previousPhase != .revealed, dock?.phase ?? .revealed == .revealed {
            presentation.edgeTilt = 0
            presentation.isActive = isVisible
        }
        setRestingFrame(frame, display: true)
    }

    func setRestingFrame(_ frame: CGRect, display: Bool) {
        stopEdgeSpring()
        dock?.restingFrame = frame
        panel.setFrame(dock?.frame ?? frame, display: display)
    }

    func saveFrame() {
        panel.saveFrame(usingName: Self.autosaveName)
    }
}
