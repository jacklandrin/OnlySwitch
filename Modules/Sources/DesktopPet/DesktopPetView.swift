import SwiftUI

public struct DesktopPetView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isActive: Bool
    private let isDragging: Bool
    private let isControlPresented: Bool

    public init(
        isActive: Bool = true,
        isDragging: Bool = false,
        isControlPresented: Bool = false
    ) {
        self.isActive = isActive
        self.isDragging = isDragging
        self.isControlPresented = isControlPresented
    }

    public var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: !isActive || isDragging || reduceMotion
            )
        ) { context in
            let motion = motionValues(at: context.date)
            DesktopPetArtwork(
                verticalOffset: motion.verticalOffset,
                eyeScale: motion.eyeScale,
                sliderOffset: isControlPresented ? 0 : motion.sliderOffset,
                isControlPresented: isControlPresented,
                isDragging: isDragging,
                reduceMotion: reduceMotion
            )
            .frame(
                width: DesktopPetMetrics.artworkSize.width,
                height: DesktopPetMetrics.artworkSize.height
            )
        }
        .frame(
            width: DesktopPetMetrics.canvasSize.width,
            height: DesktopPetMetrics.canvasSize.height
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isControlPresented ? "Hide Only Control" : "Show Only Control")
        .accessibilityHint("Click to toggle Only Control. Drag to move.")
        .accessibilityAddTraits(.isButton)
    }

    private func motionValues(at date: Date) -> MotionValues {
        guard isActive, !isDragging, !reduceMotion else { return .still }

        let seconds = date.timeIntervalSinceReferenceDate
        let breathing = sin(seconds * .pi * 2 / 3.2)
        let blinkProgress = seconds.truncatingRemainder(dividingBy: 5.4)
        let isBlinking = blinkProgress < 0.13
        let switchWave = sin(seconds * .pi * 2 / 7.0)

        return MotionValues(
            verticalOffset: breathing * 1.5,
            eyeScale: isBlinking ? 0.12 : 1,
            sliderOffset: switchWave > 0.9 ? 2.5 : 0
        )
    }
}
