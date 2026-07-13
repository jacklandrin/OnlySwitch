import CoreGraphics

enum DesktopPetMetrics {
    static let canvasSize = CGSize(width: 152, height: 160)
    static let artworkSize = CGSize(width: 120, height: 130)
    static let visibleScreenInset: CGFloat = 24

    static var artworkFrame: CGRect {
        CGRect(
            x: (canvasSize.width - artworkSize.width) / 2,
            y: (canvasSize.height - artworkSize.height) / 2,
            width: artworkSize.width,
            height: artworkSize.height
        )
    }

    static var defaultPanelInsets: CGSize {
        CGSize(
            width: visibleScreenInset - (canvasSize.width - artworkSize.width) / 2,
            height: visibleScreenInset - (canvasSize.height - artworkSize.height) / 2
        )
    }
}
