import CoreGraphics

public enum BrowserLayout {
    /// Clamp each dimension without scaling text or the web view's logical viewport.
    public static func viewportSize(_ preset: BrowserViewportSize, fitting available: CGSize) -> CGSize {
        CGSize(
            width: max(0, min(preset.size.width, available.width)),
            height: max(0, min(preset.size.height, available.height))
        )
    }
}
