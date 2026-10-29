#if os(macOS)
import AppKit
import SwiftUI

/// Reports the screen-coordinate frame of the view it backs once it is laid out in a visible window.
/// The report waits until the frame is unchanged across two samples so a popover/panel that is still opening or
/// resizing has settled, and it is retried while the window is not yet visible. Frames are reported again after later layout passes; the
/// receiver is expected to ignore repeats.
struct WindowFrameReader: NSViewRepresentable {
    let onFrame: @MainActor (CGRect) -> Void

    func makeNSView(context: Context) -> WindowFrameReaderView {
        let view = WindowFrameReaderView()
        view.onFrame = onFrame
        return view
    }

    func updateNSView(_ nsView: WindowFrameReaderView, context: Context) {
        nsView.onFrame = onFrame
        nsView.scheduleReport()
    }
}

final class WindowFrameReaderView: NSView {
    private static let settleDelay: Duration = .milliseconds(120)
    private static let maxAttempts = 12

    var onFrame: (@MainActor (CGRect) -> Void)?
    private var reportTask: Task<Void, Never>?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { reportTask?.cancel(); reportTask = nil } else { scheduleReport() }
    }

    override func layout() {
        super.layout()
        scheduleReport()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func scheduleReport() {
        reportTask?.cancel()
        reportTask = Task { @MainActor [weak self] in
            // A popover that is still opening or animating its height moves this view without laying it out
            // again, so only report once two consecutive samples agree (or on the last attempt).
            var previous: CGRect?
            for attempt in 0..<Self.maxAttempts {
                do { try await Task.sleep(for: Self.settleDelay) } catch { return }
                guard let self else { return }
                guard let frame = self.screenFrame() else { previous = nil; continue }
                if frame == previous || attempt == Self.maxAttempts - 1 {
                    self.onFrame?(frame)
                    return
                }
                previous = frame
            }
        }
    }

    private func screenFrame() -> CGRect? {
        guard let window, window.isVisible, bounds.width > 0, bounds.height > 0 else { return nil }
        let frame = window.convertToScreen(convert(bounds, to: nil))
        return frame.isEmpty || !frame.origin.x.isFinite || !frame.origin.y.isFinite ? nil : frame
    }

    isolated deinit { reportTask?.cancel() }
}
#endif
