import SwiftUI

/// A keyboard and alternating hands distinguish work even without color or movement.
struct DesktopPetWorkingIndicator: View {
    let pulse: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(red: 0.07, green: 0.12, blue: 0.28))
                .stroke(.cyan.opacity(0.65), lineWidth: 1)
                .frame(width: 54, height: 23)
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.caption.monospaced().bold())
                .foregroundStyle(.cyan)
            Capsule()
                .fill(.blue.gradient)
                .frame(width: 16, height: 8)
                .rotationEffect(.degrees(-15 + pulse * 12))
                .offset(x: -25, y: 8 - pulse * 3)
            Capsule()
                .fill(.indigo.gradient)
                .frame(width: 16, height: 8)
                .rotationEffect(.degrees(27 - pulse * 12))
                .offset(x: 25, y: 5 + pulse * 3)
        }
        .accessibilityHidden(true)
    }
}
