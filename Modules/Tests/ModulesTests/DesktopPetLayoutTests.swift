import CoreGraphics
import Testing
@testable import DesktopPet

struct DesktopPetLayoutTests {
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

    @Test func visibilityDefaultsToHidden() {
        #expect(!DesktopPetDefaults.isVisible)
    }
}
