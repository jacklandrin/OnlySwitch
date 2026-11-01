import SwiftUI

/// A small decorative symbol over a thumbnail corner (for example the pinned state).
struct RemoteScreenshotBadge: View {
    let systemImage: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if #available(iOS 26.0, *), reduceTransparency == false {
                symbol.glassEffect(.regular, in: .circle)
            } else {
                symbol.background(
                    reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.thinMaterial),
                    in: Circle()
                )
            }
        }
        .padding(6)
        .accessibilityHidden(true)
    }

    private var symbol: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(7)
    }
}
