import SwiftUI

struct DisplayVolumeHUDView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let volume: Double
    let isMuted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 26)
                .contentTransition(.symbolEffect(.replace))
            ProgressView(value: isMuted ? 0 : min(100, max(0, volume)), total: 100)
                .progressViewStyle(.linear)
                .tint(.primary)
                .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: volume)
        }
        .padding(.horizontal, 18)
        .frame(width: DisplayVolumeHUD.size.width, height: DisplayVolumeHUD.size.height)
        .modifier(DisplayVolumeHUDBackground())
        .accessibilityHidden(true)
    }

    private var symbolName: String {
        if isMuted || volume == 0 { return "speaker.slash.fill" }
        if volume < 34 { return "speaker.wave.1.fill" }
        if volume < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

private struct DisplayVolumeHUDBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}
