import SwiftUI

/// Liquid Glass on macOS 26, a regular material with a hairline border elsewhere.
struct ScheduleSurface<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.stroke(.primary.opacity(0.08)) }
        }
    }
}

extension View {
    func scheduleSurface<S: Shape>(_ shape: S) -> some View {
        modifier(ScheduleSurface(shape: shape))
    }

    /// The rounded card used for editor sections and panel rows.
    func scheduleCard(cornerRadius: CGFloat = 12) -> some View {
        scheduleSurface(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
