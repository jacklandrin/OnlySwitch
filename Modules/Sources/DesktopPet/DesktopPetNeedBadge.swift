import SwiftUI

/// A small thought bubble asking for food, shown while the pet is hungry and not eating.
struct DesktopPetNeedBadge: View {
    var body: some View {
        Image(systemName: "fork.knife")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(.orange.gradient, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1.5))
            .shadow(color: .orange.opacity(0.4), radius: 3)
            .accessibilityHidden(true)
    }
}
