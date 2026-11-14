import SwiftUI

/// Decorations around the face during a reaction. Positions are relative to the face center.
struct DesktopPetReactionOverlay: View {
    let reaction: DesktopPetReaction
    let motion: MotionValues

    var body: some View {
        ZStack {
            switch reaction {
            case .petted:
                blush(x: -15)
                blush(x: 15)
                heart(x: -10, phase: motion.heartRise)
                heart(x: 12, phase: (motion.heartRise + 0.5).truncatingRemainder(dividingBy: 1))
            case .eating:
                Image(systemName: "carrot.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.orange)
                    .scaleEffect(max(0.15, 1 - motion.reactionProgress))
                    .offset(x: 22 - motion.reactionProgress * 12, y: 2 - motion.chomp * 2)
            }
        }
        .accessibilityHidden(true)
    }

    private func blush(x: CGFloat) -> some View {
        Ellipse()
            .fill(.pink.opacity(0.55))
            .frame(width: 9, height: 5)
            .blur(radius: 1)
            .offset(x: x, y: 9)
    }

    private func heart(x: CGFloat, phase: Double) -> some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.pink)
            .opacity(1 - phase)
            .offset(x: x, y: -30 - phase * 22)
    }
}
