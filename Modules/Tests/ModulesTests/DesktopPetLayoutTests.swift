import CoreGraphics
import Testing
@testable import DesktopPet

struct DesktopPetLayoutTests {
    @Test func defaultFrameUsesLowerLeftInset() {
        let frame = DesktopPetLayout.defaultFrame(
            size: CGSize(width: 120, height: 130),
            visibleFrame: CGRect(x: 0, y: 25, width: 1_440, height: 875),
            inset: 24
        )

        #expect(frame == CGRect(x: 24, y: 49, width: 120, height: 130))
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

    @Test func visibilityDefaultsToHidden() {
        #expect(!DesktopPetDefaults.isVisible)
    }
}
