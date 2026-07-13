import CoreGraphics
import Testing
@testable import DesktopPet

struct DesktopPetLayoutTests {
    @Test func defaultFrameUsesLowerRightInset() {
        let frame = DesktopPetLayout.defaultFrame(
            size: CGSize(width: 120, height: 130),
            visibleFrame: CGRect(x: 0, y: 25, width: 1_440, height: 875),
            inset: 28
        )

        #expect(frame == CGRect(x: 1_292, y: 53, width: 120, height: 130))
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
}
