import Foundation

extension DesktopPetMotion {
    static let reactionDuration: TimeInterval = 3

    static func reactionValues(
        _ reaction: DesktopPetReaction,
        seconds: TimeInterval,
        startedAt: Date,
        now: Date,
        baseline: MotionValues
    ) -> MotionValues {
        let progress = min(max(now.timeIntervalSince(startedAt) / reactionDuration, 0), 1)
        switch reaction {
        case .eating:
            let chomp = abs(sin(seconds * .pi * 2 / 0.35))
            return MotionValues(
                verticalOffset: -chomp * 2,
                eyeScale: 1,
                sliderOffset: 0,
                badgeScale: baseline.badgeScale,
                badgeGlowOpacity: baseline.badgeGlowOpacity,
                chomp: chomp,
                reactionProgress: progress
            )
        case .petted:
            let sway = sin(seconds * .pi * 2 / 1.4)
            let elapsed = max(0, now.timeIntervalSince(startedAt))
            return MotionValues(
                verticalOffset: -abs(sway),
                horizontalOffset: sway * 1.5,
                rotationDegrees: sway * 3,
                eyeScale: 1,
                sliderOffset: 0,
                badgeScale: baseline.badgeScale,
                badgeGlowOpacity: baseline.badgeGlowOpacity,
                heartRise: elapsed.truncatingRemainder(dividingBy: 1.2) / 1.2,
                reactionProgress: progress
            )
        }
    }

    /// Slow, droopy bob with a short tummy-rumble shake every four seconds.
    static func hungryValues(seconds: TimeInterval, isBlinking: Bool, baseline: MotionValues) -> MotionValues {
        let isRumbling = seconds.truncatingRemainder(dividingBy: 4) < 0.4
        return MotionValues(
            verticalOffset: sin(seconds * .pi * 2 / 4.6) * 0.8,
            horizontalOffset: isRumbling ? sin(seconds * .pi * 2 / 0.08) * 1.2 : 0,
            eyeScale: isBlinking ? 0.12 : 0.6,
            sliderOffset: 0,
            badgeScale: baseline.badgeScale,
            badgeGlowOpacity: baseline.badgeGlowOpacity
        )
    }
}
