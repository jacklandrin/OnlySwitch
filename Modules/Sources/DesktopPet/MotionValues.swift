import Foundation

struct MotionValues: Equatable {
    let verticalOffset: Double
    let horizontalOffset: Double
    let rotationDegrees: Double
    let eyeScale: Double
    let sliderOffset: Double
    let badgeScale: Double
    let badgeGlowOpacity: Double

    init(
        verticalOffset: Double,
        horizontalOffset: Double = 0,
        rotationDegrees: Double = 0,
        eyeScale: Double,
        sliderOffset: Double,
        badgeScale: Double = 1,
        badgeGlowOpacity: Double = 0
    ) {
        self.verticalOffset = verticalOffset
        self.horizontalOffset = horizontalOffset
        self.rotationDegrees = rotationDegrees
        self.eyeScale = eyeScale
        self.sliderOffset = sliderOffset
        self.badgeScale = badgeScale
        self.badgeGlowOpacity = badgeGlowOpacity
    }

    static let still = MotionValues(
        verticalOffset: 0,
        horizontalOffset: 0,
        rotationDegrees: 0,
        eyeScale: 1,
        sliderOffset: 0,
        badgeScale: 1,
        badgeGlowOpacity: 0
    )
}

enum DesktopPetMotion {
    static func values(
        at date: Date,
        pomodoroState: DesktopPetPomodoroState?,
        isActive: Bool,
        isDragging: Bool,
        reduceMotion: Bool
    ) -> MotionValues {
        guard isActive, !isDragging, !reduceMotion else { return .still }

        let seconds = date.timeIntervalSinceReferenceDate
        let blinkProgress = seconds.truncatingRemainder(dividingBy: 5.4)
        let isBlinking = blinkProgress < 0.13
        let switchWave = sin(seconds * .pi * 2 / 7.0)

        switch pomodoroState?.phase {
        case .focus:
            let pulse = max(0, sin(seconds * .pi * 2 / 1.8))
            return MotionValues(
                verticalOffset: sin(seconds * .pi * 2 / 3.2) * 1.5,
                horizontalOffset: 0,
                rotationDegrees: 0,
                eyeScale: isBlinking ? 0.12 : 1,
                sliderOffset: switchWave > 0.9 ? 2.5 : 0,
                badgeScale: 1 + pulse * 0.03,
                badgeGlowOpacity: 0.3 + pulse * 0.35
            )
        case .breakTime:
            let sway = sin(seconds * .pi * 2 / 1.6)
            return MotionValues(
                verticalOffset: abs(sway) * -3,
                horizontalOffset: sway * 2,
                rotationDegrees: sway * 2.5,
                eyeScale: isBlinking ? 0.12 : 1,
                sliderOffset: 0,
                badgeScale: 1,
                badgeGlowOpacity: 0.5
            )
        case nil:
            return MotionValues(
                verticalOffset: sin(seconds * .pi * 2 / 3.2) * 1.5,
                horizontalOffset: 0,
                rotationDegrees: 0,
                eyeScale: isBlinking ? 0.12 : 1,
                sliderOffset: switchWave > 0.9 ? 2.5 : 0,
                badgeScale: 1,
                badgeGlowOpacity: 0
            )
        }
    }
}
