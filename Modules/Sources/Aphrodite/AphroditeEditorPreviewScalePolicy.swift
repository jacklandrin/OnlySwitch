import CoreGraphics

public struct AphroditeEditorPreviewLayout: Equatable, Sendable {
    public let logicalSize: CGSize
    public let displayedSize: CGSize
    public let scale: CGFloat

    public init(logicalSize: CGSize, displayedSize: CGSize, scale: CGFloat) {
        self.logicalSize = logicalSize
        self.displayedSize = displayedSize
        self.scale = scale
    }
}

public enum AphroditeEditorPreviewScalePolicy {
    public static func layout(content: CGSize, available: CGSize, minimumLogicalWidth: CGFloat = 640) -> AphroditeEditorPreviewLayout? {
        guard content.width.isFinite, content.height.isFinite,
              available.width.isFinite, available.height.isFinite,
              minimumLogicalWidth.isFinite,
              content.width > 0, content.height > 0,
              available.width > 0, available.height > 0,
              minimumLogicalWidth > 0 else { return nil }
        let logical = CGSize(width: max(content.width, minimumLogicalWidth), height: content.height)
        let scale = min(1, available.width / logical.width, available.height / logical.height)
        guard scale.isFinite, scale > 0 else { return nil }
        return .init(
            logicalSize: logical,
            displayedSize: CGSize(width: logical.width * scale, height: logical.height * scale),
            scale: scale
        )
    }
}
