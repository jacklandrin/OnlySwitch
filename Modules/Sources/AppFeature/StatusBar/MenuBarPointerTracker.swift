//
//  MenuBarPointerTracker.swift
//  OnlySwitch
//

import AppKit

/// Reports when the pointer moves within the menu bar, so automatic hiding can wait until the pointer has been away for the whole delay.
@MainActor
final class MenuBarPointerTracker {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onPointerInMenuBar: @MainActor () -> Void

    init(onPointerInMenuBar: @escaping @MainActor () -> Void) {
        self.onPointerInMenuBar = onPointerInMenuBar
    }

    var isTracking: Bool {
        globalMonitor != nil || localMonitor != nil
    }

    func start() {
        guard isTracking == false else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        // The global monitor misses events delivered to OnlySwitch's own status items, so a local monitor covers those.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private func pointerMoved() {
        guard Self.isPointerInMenuBar() else { return }
        onPointerInMenuBar()
    }

    static func isPointerInMenuBar() -> Bool {
        let point = NSEvent.mouseLocation
        let minimumHeight = NSStatusBar.system.thickness
        for screen in NSScreen.screens {
            if isPoint(point, inMenuBarOf: screen.frame, visibleFrame: screen.visibleFrame, minimumHeight: minimumHeight) {
                return true
            }
        }
        return false
    }

    /// The menu bar is the strip above the screen's visible frame. When the menu bar hides itself that strip is empty, so the status bar thickness stands in for it.
    nonisolated static func isPoint(_ point: CGPoint, inMenuBarOf frame: CGRect, visibleFrame: CGRect, minimumHeight: CGFloat) -> Bool {
        let height = max(frame.maxY - visibleFrame.maxY, minimumHeight)
        return point.x >= frame.minX && point.x < frame.maxX
            && point.y >= frame.maxY - height && point.y <= frame.maxY
    }
}
