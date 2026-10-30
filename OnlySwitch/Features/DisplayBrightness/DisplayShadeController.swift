import AppKit

/// A shade never changes gamma/calibration, intercepts input, or survives process exit.
@MainActor
final class DisplayShadeController {
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var factors: [CGDirectDisplayID: Double] = [:]

    func factor(for id: CGDirectDisplayID) -> Double { factors[id] ?? 1 }

    func apply(_ factor: Double, to id: CGDirectDisplayID) -> Bool {
        guard factor.isFinite, let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { return false }
        guard factor < 0.999 else { remove(id); return true }
        let panel: NSPanel
        if let existing = panels[id] { panel = existing } else {
            panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            // Status/menu UI and the cursor stay above the shade for recovery.
            panel.level = .init(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panels[id] = panel
        }
        factors[id] = max(0, min(1, factor))
        panel.setFrame(screen.frame, display: true)
        panel.alphaValue = 1 - max(0, min(1, factor))
        panel.orderFrontRegardless()
        return true
    }

    func remove(_ id: CGDirectDisplayID) {
        panels.removeValue(forKey: id)?.orderOut(nil)
        factors.removeValue(forKey: id)
    }
    func reset() {
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll(); factors.removeAll()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}
