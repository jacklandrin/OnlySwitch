import CoreGraphics

enum DesktopPetMetrics {
    static let canvasSize = CGSize(width: 152, height: 160)
    static let artworkSize = CGSize(width: 120, height: 130)
    static let visibleScreenInset: CGFloat = 24
    static let pomodoroCanvasSize = CGSize(
        width: canvasSize.width,
        height: canvasSize.height + 28
    )
    static let pomodoroTimerLane = CGRect(
        x: 0,
        y: 0,
        width: canvasSize.width,
        height: 28
    )

    static func canvasSize(for state: DesktopPetPomodoroState?) -> CGSize {
        state == nil ? canvasSize : pomodoroCanvasSize
    }

    static func artworkVerticalOffset(for state: DesktopPetPomodoroState?) -> CGFloat {
        state == nil ? 0 : 14
    }

    static func artworkOffsetY(for state: DesktopPetPomodoroState?) -> CGFloat {
        artworkFrame.minY + artworkVerticalOffset(for: state)
    }

    static func interactionSize(for state: DesktopPetPomodoroState?) -> CGSize {
        state == nil
            ? artworkSize
            : CGSize(width: artworkSize.width, height: pomodoroCanvasSize.height)
    }

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
