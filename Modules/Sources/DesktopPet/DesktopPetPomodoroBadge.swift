import SwiftUI

struct DesktopPetPomodoroBadge: View {
    let state: DesktopPetPomodoroState
    let motion: MotionValues

    var body: some View {
        HStack(spacing: 5) {
            Image(
                systemName: state.phase == .focus
                    ? "target"
                    : "cup.and.saucer.fill"
            )
            Text(state.remainingTime)
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(badgeColor, in: Capsule())
        .shadow(
            color: badgeColor.opacity(motion.badgeGlowOpacity),
            radius: 6
        )
        .scaleEffect(motion.badgeScale)
        .accessibilityHidden(true)
    }

    private var badgeColor: Color {
        state.phase == .focus ? .indigo : .mint
    }
}
