#if os(macOS)
import AppKit

/// Live fly-in overlay: a borderless, click-through panel shows the new screenshot centred on the screen of
/// the target cell and animates it into `target` (screen coordinates). Each flight owns its panel, so a newer
/// capture never fights an older animation.
@MainActor
public final class ScreenshotFlyInPresenter {
    public static let shared = ScreenshotFlyInPresenter()

    private static let duration: TimeInterval = 0.55
    private static let startScreenFraction: CGFloat = 0.45
    private static let cornerRadius: CGFloat = 10
    private var activePanels: [ObjectIdentifier: NSPanel] = [:]

    public init() {}

    /// Returns when the image has landed. An unreadable image or an empty target returns immediately. Cancelling
    /// the calling task (a newer capture, or the item was deleted mid-flight) removes the panel at once.
    public func fly(_ url: URL, to target: CGRect) async {
        guard !Task.isCancelled, !target.isEmpty, let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(target) }) ?? NSScreen.main else { return }
        let start = Self.startFrame(for: image.size, in: screen.visibleFrame)
        let panel = Self.makePanel(image: image, frame: start)
        let key = ObjectIdentifier(panel)
        activePanels[key] = panel
        panel.orderFrontRegardless()

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.duration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    context.allowsImplicitAnimation = true
                    panel.animator().setFrame(target, display: true)
                    panel.animator().alphaValue = 0.9
                } completionHandler: {
                    continuation.resume()
                }
            }
        } onCancel: {
            // The animation's completion still resumes the continuation; only hide the stale panel now.
            Task { @MainActor in panel.orderOut(nil) }
        }

        panel.orderOut(nil)
        activePanels[key] = nil
    }

    /// The image fitted into a fraction of the visible frame, centred.
    static func startFrame(for imageSize: CGSize, in visibleFrame: CGRect) -> CGRect {
        let bounds = CGSize(width: visibleFrame.width * startScreenFraction, height: visibleFrame.height * startScreenFraction)
        let scale = min(1, bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: max(1, imageSize.width * scale), height: max(1, imageSize.height * scale))
        return CGRect(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2, width: size.width, height: size.height).integral
    }

    private static func makePanel(image: NSImage, frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above the status bar and above a status item's popover window, which can sit higher than `.statusBar`.
        panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.statusBar.rawValue, NSWindow.Level.popUpMenu.rawValue) + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = cornerRadius
        imageView.layer?.masksToBounds = true
        imageView.setAccessibilityElement(false)
        panel.contentView = imageView
        panel.alphaValue = 1
        return panel
    }
}
#endif
