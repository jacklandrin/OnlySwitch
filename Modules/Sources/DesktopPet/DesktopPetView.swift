import SwiftUI

public struct DesktopPetView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isActive: Bool
    private let isDragging: Bool

    public init(isActive: Bool = true, isDragging: Bool = false) {
        self.isActive = isActive
        self.isDragging = isDragging
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
                sliderOffset: motion.sliderOffset,
                isDragging: isDragging
            )
        }
        .frame(width: 120, height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open Only Control")
        .accessibilityHint("Click to open Only Control. Drag to move.")
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
