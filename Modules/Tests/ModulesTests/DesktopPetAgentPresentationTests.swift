import CoreGraphics
import Foundation
import Testing
@testable import DesktopPet

struct DesktopPetAgentPresentationTests {
    @Test(arguments: [false, true], [false, true])
    func leftAgentBubbleCoexistsWithPlaybackAndPomodoro(showsPlayback: Bool, showsPomodoro: Bool) {
        let timer: DesktopPetPomodoroState? = showsPomodoro ? .init(phase: .focus, remainingTime: "24:59") : nil
        let original = DesktopPetMetrics.canvasSize(for: timer, showsPlayback: showsPlayback)
        let expanded = DesktopPetMetrics.canvasSize(for: timer, showsPlayback: showsPlayback, showsAgentStatus: true)

        #expect(expanded.width == original.width + DesktopPetMetrics.agentStatusWidth + DesktopPetMetrics.agentStatusGap)
        #expect(expanded.height == max(original.height, DesktopPetMetrics.agentStatusHeight))
        #expect(expanded.width >= original.width)
        let frame = CGRect(origin: CGPoint(x: 100, y: 200), size: original)
        let resized = DesktopPetLayout.resizedFramePreservingPet(frame, to: expanded)
        #expect(resized.maxX == frame.maxX)
        #expect(resized.minX == frame.minX - DesktopPetMetrics.agentStatusWidth - DesktopPetMetrics.agentStatusGap)
        #expect(resized.midY == frame.midY)
    }

    @Test func completionBubbleUsesCompactBoundsWithoutVerticalExpansion() {
        #expect(DesktopPetMetrics.agentStatusWidth == 148)
        #expect(DesktopPetMetrics.agentStatusHeight == 40)
        #expect(DesktopPetMetrics.canvasSize(for: nil, showsAgentStatus: true) == CGSize(width: 308, height: 160))
    }

    @Test func togglingLeftStatusPreservesPetAnchor() {
        let original = CGRect(x: 500, y: 200, width: 152, height: 160)
        let expandedSize = DesktopPetMetrics.canvasSize(for: nil, showsAgentStatus: true)
        let expanded = DesktopPetLayout.resizedFramePreservingPet(original, to: expandedSize)
        let restored = DesktopPetLayout.resizedFramePreservingPet(expanded, to: DesktopPetMetrics.canvasSize)

        #expect(expanded.maxX == original.maxX)
        #expect(expanded.minX + DesktopPetMetrics.agentStatusWidth + DesktopPetMetrics.agentStatusGap == original.minX)
        #expect(restored == original)
    }

    @Test(arguments: [CGFloat(308), CGFloat(384)])
    func restoringExpandedSavedFramePreservesPetRatherThanPanelCenter(width: CGFloat) {
        let saved = CGRect(x: 652 - width, y: 200, width: width, height: 160)
        let restored = DesktopPetLayout.restoredFramePreservingPet(saved, to: DesktopPetMetrics.canvasSize)

        #expect(restored == CGRect(x: 500, y: 200, width: 152, height: 160))
        #expect(restored.maxX == saved.maxX)
    }

    @Test(arguments: [CGSize(width: 120, height: 130), CGSize(width: 152, height: 160), CGSize(width: 224, height: 256)])
    func restoringLegacySavedFramesPreservesTheirCenter(size: CGSize) {
        let saved = CGRect(origin: CGPoint(x: 100, y: 200), size: size)
        let restored = DesktopPetLayout.restoredFramePreservingPet(saved, to: DesktopPetMetrics.canvasSize)

        #expect(restored.midX == saved.midX)
        #expect(restored.midY == saved.midY)
    }

    @Test(arguments: [false, true])
    func statusAlignsWithPetBodyIndependentlyOfMusic(showsPomodoro: Bool) {
        let timer: DesktopPetPomodoroState? = showsPomodoro ? .init(phase: .focus, remainingTime: "24:59") : nil
        let petHeight = DesktopPetMetrics.canvasSize(for: timer).height
        let statusCenter = DesktopPetMetrics.agentStatusBottomPadding(for: timer) + DesktopPetMetrics.agentStatusHeight / 2
        #expect(statusCenter == petHeight / 2)
    }

    @Test func workingMotionIsDistinctAndContinuesOverTime() {
        let date = Date(timeIntervalSinceReferenceDate: 0.15)
        let idle = motion(at: date)
        let working = motion(at: date, working: true)
        let later = motion(at: date.addingTimeInterval(0.2), working: true)

        #expect(working != idle)
        #expect(working != later)
        #expect(working.horizontalOffset != 0)
        #expect(working.rotationDegrees != 0)
    }

    @Test(arguments: [
        (active: false, dragging: false, reduced: false),
        (active: true, dragging: true, reduced: false),
        (active: true, dragging: false, reduced: true)
    ])
    func workingMotionStopsWhenAnimationCannotBePresented(state: (active: Bool, dragging: Bool, reduced: Bool)) {
        let values = DesktopPetMotion.values(
            at: Date(timeIntervalSinceReferenceDate: 0.15), pomodoroState: nil,
            isActive: state.active, isDragging: state.dragging, reduceMotion: state.reduced,
            isAgentWorking: true
        )
        #expect(values == .still)
    }

    @Test(arguments: [DesktopPetPomodoroPhase.focus, .breakTime])
    func workingMotionPreservesTimerBadge(phase: DesktopPetPomodoroPhase) {
        let date = Date(timeIntervalSinceReferenceDate: 0.6)
        let timer = DesktopPetPomodoroState(phase: phase, remainingTime: "10:00")
        let baseline = motion(at: date, timer: timer)
        let working = motion(at: date, timer: timer, working: true)

        #expect(working.badgeScale == baseline.badgeScale)
        #expect(working.badgeGlowOpacity == baseline.badgeGlowOpacity)
    }

    private func motion(at date: Date, timer: DesktopPetPomodoroState? = nil, working: Bool = false) -> MotionValues {
        DesktopPetMotion.values(
            at: date, pomodoroState: timer, isActive: true, isDragging: false,
            reduceMotion: false, isAgentWorking: working
        )
    }
}
