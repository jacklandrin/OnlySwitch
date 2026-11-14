import CoreGraphics

enum DesktopPetMetrics {
    static let canvasSize = CGSize(width: 152, height: 160)
    static let artworkSize = CGSize(width: 120, height: 130)
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

    static func canvasSize(
        for state: DesktopPetPomodoroState?,
        showsPlayback: Bool = false,
        showsAgentStatus: Bool = false
    ) -> CGSize {
        let petSize = state == nil ? canvasSize : pomodoroCanvasSize
        let petStackHeight = petSize.height
            + (showsPlayback ? nowPlayingLaneHeight + playbackLaneHeight(for: state) : 0)
        return CGSize(
            width: petSize.width + (showsAgentStatus ? agentStatusWidth + agentStatusGap : 0),
            height: showsAgentStatus ? max(petStackHeight, agentStatusHeight) : petStackHeight
        )
    }

    static let agentStatusWidth: CGFloat = 148
    static let agentStatusHeight: CGFloat = 40
    static let agentStatusGap: CGFloat = 8

    static func agentStatusBottomPadding(for state: DesktopPetPomodoroState?) -> CGFloat {
        max(0, (canvasSize(for: state).height - agentStatusHeight) / 2)
    }

    /// Reserved even without now-playing text, so the panel does not resize between tracks.
    static let nowPlayingLaneHeight: CGFloat = 36
    static let nowPlayingSize = CGSize(width: 140, height: 32)
    static let nowPlayingHorizontalPadding: CGFloat = 10

    static func playbackLaneHeight(for state: DesktopPetPomodoroState?) -> CGFloat {
        state == nil ? 16 : 32
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
}
