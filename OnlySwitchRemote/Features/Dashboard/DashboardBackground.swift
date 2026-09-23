import SwiftUI

struct DashboardBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)

            if showsColorLayers {
                LinearGradient(
                    colors: [leadingTint, .clear, trailingTint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [topTrailingGlow, .clear],
                    center: .topTrailing,
                    startRadius: 24,
                    endRadius: 460
                )

                RadialGradient(
                    colors: [bottomLeadingGlow, .clear],
                    center: .bottomLeading,
                    startRadius: 24,
                    endRadius: 440
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var showsColorLayers: Bool {
        reduceTransparency == false && colorSchemeContrast != .increased
    }

    private var leadingTint: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.15, blue: 0.31).opacity(0.58)
            : Color(red: 0.64, green: 0.78, blue: 0.96).opacity(0.34)
    }

    private var trailingTint: Color {
        colorScheme == .dark
            ? Color(red: 0.25, green: 0.13, blue: 0.34).opacity(0.48)
            : Color(red: 0.82, green: 0.70, blue: 0.94).opacity(0.28)
    }

    private var topTrailingGlow: Color {
        colorScheme == .dark
            ? Color(red: 0.31, green: 0.18, blue: 0.48).opacity(0.36)
            : Color(red: 0.76, green: 0.62, blue: 0.94).opacity(0.30)
    }

    private var bottomLeadingGlow: Color {
        colorScheme == .dark
            ? Color(red: 0.05, green: 0.34, blue: 0.33).opacity(0.38)
            : Color(red: 0.55, green: 0.86, blue: 0.78).opacity(0.32)
    }
}
