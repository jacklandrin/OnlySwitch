import SwiftUI

struct DesktopPetPomodoroBadge: View {
    let state: DesktopPetPomodoroState
    let isActive: Bool
    let isDragging: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: !isActive || isDragging || reduceMotion
            )
        ) { context in
            let motion = DesktopPetMotion.values(
                at: context.date,
                pomodoroState: state,
                isActive: isActive,
                isDragging: isDragging,
                reduceMotion: reduceMotion
            )

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
        }
        .accessibilityHidden(true)
    }

    private var badgeColor: Color {
        state.phase == .focus ? .indigo : .mint
    }
}
