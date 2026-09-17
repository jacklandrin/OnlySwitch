import CoreGraphics
import Foundation
import Testing
@testable import DesktopPet

struct DesktopPetLayoutTests {
    @Test func pomodoroStatePreservesPhaseAndCountdown() {
        let state = DesktopPetPomodoroState(phase: .focus, remainingTime: "24:59")

        #expect(state.phase == .focus)
        #expect(state.remainingTime == "24:59")
        #expect(
            state != DesktopPetPomodoroState(
                phase: .breakTime,
                remainingTime: "24:59"
            )
        )
    }

    @Test func focusMotionPulsesWithoutSway() {
        let values = DesktopPetMotion.values(
            at: Date(timeIntervalSinceReferenceDate: 0.6),
            pomodoroState: .init(phase: .focus, remainingTime: "24:59"),
            isActive: true,
            isDragging: false,
            reduceMotion: false
        )

        #expect(values.badgeScale > 1)
        #expect(values.badgeGlowOpacity > 0)
        #expect(values.horizontalOffset == 0)
        #expect(values.rotationDegrees == 0)
    }

    @Test func breakMotionSwaysAndBounces() {
        let values = DesktopPetMotion.values(
            at: Date(timeIntervalSinceReferenceDate: 0.45),
            pomodoroState: .init(phase: .breakTime, remainingTime: "04:59"),
            isActive: true,
            isDragging: false,
            reduceMotion: false
        )

        #expect(values.verticalOffset != 0)
        #expect(values.horizontalOffset != 0)
        #expect(values.rotationDegrees != 0)
    }

    @Test func reducedMotionFreezesBothPomodoroAnimations() {
        for phase in [DesktopPetPomodoroPhase.focus, .breakTime] {
            let values = DesktopPetMotion.values(
                at: Date(timeIntervalSinceReferenceDate: 1),
                pomodoroState: .init(phase: phase, remainingTime: "10:00"),
                isActive: true,
                isDragging: false,
                reduceMotion: true
            )

            #expect(values == .still)
        }
    }

    @Test func inactivePomodoroPetIsStill() {
        let values = DesktopPetMotion.values(
            at: Date(timeIntervalSinceReferenceDate: 1),
            pomodoroState: .init(phase: .focus, remainingTime: "10:00"),
            isActive: false,
            isDragging: false,
            reduceMotion: false
        )

        #expect(values == .still)
    }

    @Test func draggedPomodoroPetIsStill() {
        let values = DesktopPetMotion.values(
            at: Date(timeIntervalSinceReferenceDate: 1),
            pomodoroState: .init(phase: .breakTime, remainingTime: "04:59"),
            isActive: true,
            isDragging: true,
            reduceMotion: false
        )

        #expect(values == .still)
    }

    @Test func pomodoroCanvasMakesTheTimerBadgeInteractive() {
        let state = DesktopPetPomodoroState(phase: .focus, remainingTime: "25:00")
        let size = DesktopPetMetrics.interactionSize(for: state)
        let bounds = DesktopPetInteractionShape(size: size)
            .path(in: CGRect(origin: .zero, size: DesktopPetMetrics.canvasSize(for: state)))
            .boundingRect
        let canvas = DesktopPetMetrics.canvasSize(for: state)
        let artworkMinY = DesktopPetMetrics.artworkFrame.minY
            + DesktopPetMetrics.artworkVerticalOffset(for: state)

        #expect(bounds.minY <= DesktopPetMetrics.pomodoroTimerLane.minY)
        #expect(bounds.maxY >= artworkMinY + DesktopPetMetrics.artworkSize.height)
        #expect(
            bounds.contains(
                CGPoint(x: bounds.midX, y: DesktopPetMetrics.pomodoroTimerLane.midY)
            )
        )
        #expect(bounds.contains(CGPoint(x: bounds.midX, y: artworkMinY + 4)))
        #expect(bounds.maxY <= canvas.height)
    }

    @Test func pomodoroBadgeStartsAtCanvasTopAndArtworkUsesLayoutOffset() {
        let activeState = DesktopPetPomodoroState(
            phase: .focus,
            remainingTime: "25:00"
        )
        let idleArtworkOffsetY = DesktopPetMetrics.artworkOffsetY(for: nil)
        let activeArtworkOffsetY = DesktopPetMetrics.artworkOffsetY(for: activeState)

        #expect(DesktopPetMetrics.pomodoroTimerLane.minY == 0)
        #expect(idleArtworkOffsetY == DesktopPetMetrics.artworkFrame.minY)
        #expect(activeArtworkOffsetY >= DesktopPetMetrics.pomodoroTimerLane.maxY)
        #expect(
            activeArtworkOffsetY
                == DesktopPetMetrics.artworkFrame.minY
                + DesktopPetMetrics.artworkVerticalOffset(for: activeState)
        )
    }

    @Test func expandedCanvasKeepsArtworkBoundaryAtRequestedInset() {
        let frame = DesktopPetLayout.defaultFrame(
            size: DesktopPetMetrics.canvasSize,
            visibleFrame: CGRect(x: 0, y: 25, width: 1_440, height: 875),
            horizontalInset: DesktopPetMetrics.defaultPanelInsets.width,
            verticalInset: DesktopPetMetrics.defaultPanelInsets.height
        )

        #expect(frame == CGRect(x: 8, y: 34, width: 152, height: 160))
        #expect(frame.minX + 16 == 24)
        #expect(frame.minY + 15 == 49)
    }

    @Test func resizingLegacyFramePreservesItsCenter() {
        let frame = DesktopPetLayout.resizedFramePreservingCenter(
            CGRect(x: 24, y: 49, width: 120, height: 130),
            to: DesktopPetMetrics.canvasSize
        )

        #expect(frame == CGRect(x: 8, y: 34, width: 152, height: 160))
    }

    @Test func artworkInteractionFrameIsCenteredWithinCanvas() {
        #expect(
            DesktopPetMetrics.artworkFrame
                == CGRect(x: 16, y: 15, width: 120, height: 130)
        )
    }

    @Test func interactionShapeMatchesOriginalPetBounds() {
        let shape = DesktopPetInteractionShape(size: DesktopPetMetrics.artworkSize)
        let bounds = shape.path(
            in: CGRect(origin: .zero, size: DesktopPetMetrics.canvasSize)
        ).boundingRect

        #expect(bounds == CGRect(x: 16, y: 15, width: 120, height: 130))
    }

    @Test func frameIsClampedInsideVisibleFrame() {
        let frame = DesktopPetLayout.constrainedFrame(
            CGRect(x: -50, y: 850, width: 120, height: 130),
            to: CGRect(x: 0, y: 25, width: 1_440, height: 875)
        )

        #expect(frame == CGRect(x: 0, y: 770, width: 120, height: 130))
    }

    @Test func screenWithLargestIntersectionWins() {
        let index = DesktopPetLayout.bestScreenIndex(
            for: CGRect(x: 1_390, y: 100, width: 120, height: 130),
            visibleFrames: [
                CGRect(x: 0, y: 0, width: 1_440, height: 900),
                CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080)
            ]
        )

        #expect(index == 1)
    }

    @Test func nearestScreenWinsWhenPetIsFullyOffscreen() {
        let index = DesktopPetLayout.bestScreenIndex(
            for: CGRect(x: 2_600, y: 1_500, width: 120, height: 130),
            visibleFrames: [
                CGRect(x: 0, y: 0, width: 1_440, height: 900),
                CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080)
            ]
        )

        #expect(index == 1)
    }

    @Test func clickThresholdDistinguishesDrag() {
        #expect(DesktopPetInteraction.isClick(translation: .init(width: 2, height: 3)))
        #expect(!DesktopPetInteraction.isClick(translation: .init(width: 8, height: 0)))
    }

    @Test func draggedOriginUsesStableScreenMouseDelta() {
        let origin = DesktopPetInteraction.draggedOrigin(
            startOrigin: CGPoint(x: 24, y: 49),
            startMouseLocation: CGPoint(x: 70, y: 100),
            currentMouseLocation: CGPoint(x: 100, y: 120)
        )

        #expect(origin == CGPoint(x: 54, y: 69))
    }

    @Test @MainActor func controllerStartsHidden() {
        let controller = DesktopPetController(onActivate: {})

        #expect(!controller.isVisible)
    }

    @Test @MainActor func controllerTracksControlPresentation() {
        let controller = DesktopPetController(onActivate: {})

        controller.setControlPresented(true)

        #expect(controller.isControlPresented)
    }

    @Test @MainActor func controllerRoutesCloseRequest() {
        var didClose = false
        let controller = DesktopPetController(
            onActivate: {},
            onClose: { didClose = true }
        )

        controller.close()

        #expect(didClose)
    }

    @Test @MainActor func controllerPublishesPomodoroState() {
        let controller = DesktopPetController(onActivate: {})
        let state = DesktopPetPomodoroState(phase: .focus, remainingTime: "24:59")

        controller.setPomodoroState(state)

        #expect(controller.pomodoroState == state)
    }

    @Test @MainActor func clearingPomodoroStateRestoresNormalPanelSize() {
        let controller = DesktopPetController(onActivate: {})
        controller.setPomodoroState(.init(phase: .breakTime, remainingTime: "04:59"))

        #expect(controller.contentSize == DesktopPetMetrics.pomodoroCanvasSize)

        controller.setPomodoroState(nil)

        #expect(controller.contentSize == DesktopPetMetrics.canvasSize)
    }

    @Test func visibilityDefaultsToHidden() {
        #expect(!DesktopPetDefaults.isVisible)
    }
}
