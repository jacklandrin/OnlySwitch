import SwiftUI

struct RemoteCodexUsageCardSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .overlay { if contrast == .increased { RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.45), lineWidth: 2) } }
        } else {
            content
                .background(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.regularMaterial), in: RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(contrast == .increased ? 0.45 : 0.08), lineWidth: contrast == .increased ? 2 : 1) }
        }
    }
}

extension View {
    func remoteCodexCardSurface() -> some View { modifier(RemoteCodexUsageCardSurface()) }
}
