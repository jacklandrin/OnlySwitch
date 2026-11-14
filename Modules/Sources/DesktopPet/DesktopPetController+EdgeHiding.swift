import AppKit
import SwiftUI

extension DesktopPetController {
    func updateEdgeTracking() {
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

    func stopEdgeTracking() {
        cancelPendingPhase()
        stopEdgeSpring()
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
    }

    func updateEdgeVisibility() {
        guard isVisible, let dock, dragStartOrigin == nil else { return }

        let wanted = edgePhase(for: dock)

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

    /// The mouse-driven phase, raised to the least the pet may retreat while it has needs to show.
    private func edgePhase(for dock: Dock) -> DesktopPetEdgePhase {
        let mouse = DesktopPetEdgeDocking.phase(
            forMouseLocation: NSEvent.mouseLocation,
            restingFrame: dock.restingFrame,
            edge: dock.edge,
            screenFrame: dock.screenFrame,
            current: dock.phase
        )
        let minimum = DesktopPetEdgeDocking.minimumPhase(
            isControlPresented: presentation.isControlPresented, hasCompletion: activityStore.completion != nil,
            hasReaction: needsStore.reaction != nil, isHungry: needsStore.isHungry
        )
        return minimum.visibility > mouse.visibility ? minimum : mouse
    }

    /// Steps back toward hidden once the linger delay has passed, if the mouse is still away.
    private func retreatIfMouseIsAway() {
        guard isVisible, let dock, dragStartOrigin == nil else { return }
        let wanted = edgePhase(for: dock)
        if wanted.visibility < dock.phase.visibility {
            setEdgePhase(wanted)
        }
    }

    func cancelPendingPhase() {
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

    func stopEdgeSpring() {
        edgeSpring = nil
        edgeDisplayLink?.invalidate()
        edgeDisplayLink = nil
    }
}
