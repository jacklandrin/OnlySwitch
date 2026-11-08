import AppKit
import Extensions
import SwiftUI

/// Stands in for the system volume HUD, whose private OSDUIHelper entry point draws nothing on macOS 26+.
@MainActor
final class DisplayVolumeHUD {
    static let size = CGSize(width: 240, height: 48)

    private var panel: NSPanel?
    private var hostingView: NSHostingView<DisplayVolumeHUDView>?
    private var hideTask: Task<Void, Never>?

    func show(volume: Double, isMuted: Bool, onScreenNamed screenName: String?) {
        let panel = panel ?? makePanel()
        self.panel = panel
        // Updating one hosting view lets the level bar and symbol animate between presses.
        let rootView = DisplayVolumeHUDView(volume: volume, isMuted: isMuted)
        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hostingView = NSHostingView(rootView: rootView)
            panel.contentView = hostingView
            self.hostingView = hostingView
        }
        let screen = NSScreen.screens.first { $0.localizedName == screenName } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: frame.maxX - Self.size.width - 12,
                                         y: frame.maxY - Self.size.height - 8))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        announce(volume: volume, isMuted: isMuted)

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let panel = self?.panel else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    private func announce(volume: Double, isMuted: Bool) {
        let text = isMuted ? "Muted".localized() : "\("Volume".localized()) \(Int(volume.rounded()))%"
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
