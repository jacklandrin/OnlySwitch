import CoreGraphics

public struct AdaptivePanelHeightPolicy: Sendable, Equatable {
    public static func availableContentHeight(screenHeight: CGFloat, windowHeight: CGFloat, contentLayoutHeight: CGFloat) -> CGFloat {
        let screen = screenHeight.isFinite && screenHeight > 0 ? screenHeight : 0
        let window = windowHeight.isFinite && windowHeight > 0 ? windowHeight : 0
        let content = contentLayoutHeight.isFinite && contentLayoutHeight > 0 ? contentLayoutHeight : 0
        return max(0, screen - max(0, window - content))
    }

    public var minimumContentHeight: CGFloat
    public var chromeHeight: CGFloat
    public var maximumPanelHeight: CGFloat

    public init(minimumContentHeight: CGFloat, chromeHeight: CGFloat, maximumPanelHeight: CGFloat) {
        self.minimumContentHeight = minimumContentHeight
        self.chromeHeight = chromeHeight
        self.maximumPanelHeight = maximumPanelHeight
    }

    public func panelHeight(for contentHeight: CGFloat?) -> CGFloat {
        let minimum = max(0, minimumContentHeight.isFinite ? minimumContentHeight : 0)
        let chrome = max(0, chromeHeight.isFinite ? chromeHeight : 0)
        let maximum = max(0, maximumPanelHeight.isFinite ? maximumPanelHeight : 0)
        let content = contentHeight.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? minimum
        return min(maximum, max(minimum, content) + chrome)
    }
}
