import AppKit
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
    private let panel: DesktopPetPanel
    private let playbackStore: StoreOf<DesktopPetPlaybackFeature>
    private let presentation = DesktopPetPresentation()
    private var dragStartOrigin: CGPoint?
    private var dragStartMouseLocation: CGPoint?
    private var restoredFrame = false
    private var dock: Dock?
    private var mouseMonitors: [Any] = []
    private var pendingPhaseTask: Task<Void, Never>?
    private var edgeSpring: DesktopPetSpring?
    private var edgeDisplayLink: CADisplayLink?

    /// A pet pushed against a screen edge, which hides behind it until the mouse comes near that edge.
    private struct Dock {
        var edge: DesktopPetDockEdge
        var screenFrame: CGRect
        var restingFrame: CGRect
        var phase = DesktopPetEdgePhase.revealed

        var frame: CGRect {
            DesktopPetEdgeDocking.frame(for: phase, restingFrame: restingFrame, edge: edge, screenFrame: screenFrame)
        }
    }

    /// The on-screen frame, even while the pet is hidden behind a screen edge.
    private var restingFrame: CGRect {
        dock?.restingFrame ?? panel.frame
    }

    public init(
        onActivate: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void = {},
        playbackClient: DesktopPetPlaybackClient = .init()
    ) {
        playbackStore = Store(initialState: DesktopPetPlaybackFeature.State()) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playbackClient
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
        stopEdgeTracking()
    }

    public func show() {
        restoreFrameIfNeeded()
        setRestingFrame(
            DesktopPetLayout.resizedFramePreservingCenter(
                restingFrame,
                to: DesktopPetMetrics.canvasSize(for: pomodoroState, showsPlayback: playbackStore.source != nil)
            ),
            display: false
        )
        constrainPanelToVisibleScreen()
        saveFrame()
        presentation.isActive = true
        isVisible = true
        panel.orderFrontRegardless()
        updateEdgeTracking()
    }

    public func hide() {
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

    private func resizeForPlayback(_ showsPlayback: Bool) {
        setRestingFrame(
            DesktopPetLayout.resizedFramePreservingCenter(
                restingFrame,
                to: DesktopPetMetrics.canvasSize(for: pomodoroState, showsPlayback: showsPlayback)
            ),
            display: isVisible
        )
        constrainPanelToVisibleScreen()
        saveFrame()
    }

    public func setControlPresented(_ isPresented: Bool) {
        presentation.isControlPresented = isPresented
        updateEdgeVisibility()
    }

    public func setPomodoroState(_ state: DesktopPetPomodoroState?) {
        guard pomodoroState != state else { return }

        pomodoroState = state
        presentation.pomodoroState = state
        setRestingFrame(
            DesktopPetLayout.resizedFramePreservingCenter(
                restingFrame,
                to: DesktopPetMetrics.canvasSize(for: state, showsPlayback: playbackStore.source != nil)
            ),
            display: isVisible
        )
        constrainPanelToVisibleScreen()
        saveFrame()
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
                onPlaybackVisibilityChanged: { [weak self] isShown in
                    self?.resizeForPlayback(isShown)
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

    private func constrainPanelToVisibleScreen() {
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

    private func setRestingFrame(_ frame: CGRect, display: Bool) {
        stopEdgeSpring()
        dock?.restingFrame = frame
        panel.setFrame(dock?.frame ?? frame, display: display)
    }

    // MARK: - Edge hiding

    private func updateEdgeTracking() {
        guard isVisible, dock != nil else {
            stopEdgeTracking()
            return
        }
        startEdgeTracking()
        updateEdgeVisibility()
    }

    private func startEdgeTracking() {
        guard mouseMonitors.isEmpty else { return }

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            Task { @MainActor in
                self?.updateEdgeVisibility()
            }
        }) {
            mouseMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            Task { @MainActor in
                self?.updateEdgeVisibility()
            }
            return event
        }) {
            mouseMonitors.append(monitor)
        }
    }

    private func stopEdgeTracking() {
        cancelPendingPhase()
        stopEdgeSpring()
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
    }

    private func updateEdgeVisibility() {
        guard isVisible, let dock, dragStartOrigin == nil else { return }

        let wanted = presentation.isControlPresented
            ? .revealed
            : DesktopPetEdgeDocking.phase(
                forMouseLocation: NSEvent.mouseLocation,
                restingFrame: dock.restingFrame,
                edge: dock.edge,
                screenFrame: dock.screenFrame,
                current: dock.phase
            )

        if wanted.visibility >= dock.phase.visibility {
            cancelPendingPhase()
            setEdgePhase(wanted)
        } else if pendingPhaseTask == nil {
            // Linger before retreating so a brief mouse slip does not make the pet flicker away.
            let delay: Duration = dock.phase == .revealed ? .seconds(2) : .milliseconds(250)
            pendingPhaseTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                pendingPhaseTask = nil
                retreatIfMouseIsAway()
            }
        }
    }

    /// Steps back toward hidden once the linger delay has passed, if the mouse is still away.
    private func retreatIfMouseIsAway() {
        guard isVisible, let dock, dragStartOrigin == nil, !presentation.isControlPresented else { return }
        let wanted = DesktopPetEdgeDocking.phase(
            forMouseLocation: NSEvent.mouseLocation,
            restingFrame: dock.restingFrame,
            edge: dock.edge,
            screenFrame: dock.screenFrame,
            current: dock.phase
        )
        if wanted.visibility < dock.phase.visibility {
            setEdgePhase(wanted)
        }
    }

    private func cancelPendingPhase() {
        pendingPhaseTask?.cancel()
        pendingPhaseTask = nil
    }

    private func setEdgePhase(_ phase: DesktopPetEdgePhase) {
        guard var dock else { return }
        let target = DesktopPetEdgeDocking.frame(
            for: phase,
            restingFrame: dock.restingFrame,
            edge: dock.edge,
            screenFrame: dock.screenFrame
        )
        let isMoving = edgeSpring != nil
        guard dock.phase != phase || (!isMoving && panel.frame.origin != target.origin) else { return }

        dock.phase = phase
        self.dock = dock
        if phase != .hidden {
            presentation.isActive = true
        }
        presentation.edgeTilt = DesktopPetEdgeDocking.tilt(for: phase, edge: dock.edge)

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stopEdgeSpring()
            panel.setFrame(target, display: true)
            presentation.isActive = phase != .hidden
            return
        }

        let motion: DesktopPetSpringMotion = switch phase {
        case .hidden: .hide(edge: dock.edge)
        case .peeking: .peek(edge: dock.edge)
        case .revealed: .pop(edge: dock.edge)
        }
        edgeSpring = DesktopPetSpring(position: panel.frame.origin, target: target.origin, motion: motion)
        // Tie the link to the docked screen: a hidden panel is off every screen, so its own link would stall.
        if edgeDisplayLink == nil,
           let screen = NSScreen.screens.first(where: { $0.frame == dock.screenFrame }) ?? NSScreen.main {
            let link = screen.displayLink(target: self, selector: #selector(stepEdgeSpring(_:)))
            link.add(to: .main, forMode: .common)
            edgeDisplayLink = link
        }
    }

    @objc private func stepEdgeSpring(_ link: CADisplayLink) {
        guard var spring = edgeSpring else {
            stopEdgeSpring()
            return
        }
        spring.step(by: min(link.targetTimestamp - link.timestamp, 1.0 / 30.0))
        edgeSpring = spring
        panel.setFrameOrigin(spring.position)

        if spring.isSettled {
            stopEdgeSpring()
            if dock?.phase == .hidden {
                presentation.isActive = false
            }
        }
    }

    private func stopEdgeSpring() {
        edgeSpring = nil
        edgeDisplayLink?.invalidate()
        edgeDisplayLink = nil
    }

    private func saveFrame() {
        panel.saveFrame(usingName: Self.autosaveName)
    }
}

private extension DesktopPetEdgePhase {
    /// Orders phases by how much of the pet is on screen.
    var visibility: Int {
        switch self {
        case .hidden: 0
        case .peeking: 1
        case .revealed: 2
        }
    }
}
