import SwiftUI

struct DesktopPetPlaybackButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let onNext: @MainActor () -> Void

    var body: some View {
        Button(action: onNext) {
            Label(String(localized: "Desktop pet Next", bundle: .main), systemImage: "forward.end.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
        }
        .buttonStyle(.plain)
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
}
