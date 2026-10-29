import SwiftUI

struct DesktopPetPlaybackButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let title: String
    let systemImage: String
    var showsTitle = true
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            label
                .font(.caption.weight(.semibold))
                .padding(.horizontal, showsTitle ? 10 : 0)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
        .modifier(DesktopPetPlaybackButtonBackground())
        .overlay {
            Capsule()
                .fill(.cyan.opacity(isHovered ? 0.16 : 0))
                .allowsHitTesting(false)
        }
        .shadow(color: .cyan.opacity(isHovered ? 0.35 : 0), radius: 5, y: 1)
        .scaleEffect(isHovered && !reduceMotion ? 1.06 : 1)
        .offset(y: isHovered && !reduceMotion ? -1 : 0)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var label: some View {
        if showsTitle {
            Label(title, systemImage: systemImage)
        } else {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
    }
}
