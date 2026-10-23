import SwiftUI

struct DesktopPetMusicEqualizer: View {
    let pulse: Double
    let counterPulse: Double

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            Capsule()
                .frame(width: 3, height: 4 + pulse * 7)
            Capsule()
                .frame(width: 3, height: 5 + counterPulse * 8)
            Capsule()
                .frame(width: 3, height: 4 + (1 - pulse) * 7)
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: 19, height: 13)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
