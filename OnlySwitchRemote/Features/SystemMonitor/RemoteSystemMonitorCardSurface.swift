import SwiftUI

struct RemoteSystemMonitorCardSurface: View {
    static var lightModeShadowOpacity: Double { 0.12 }

    private let content: AnyView
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    init<Content: View>(@ViewBuilder content: () -> Content) {
        self.content = AnyView(content())
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *), reduceTransparency == false {
            decoratedContent
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            decoratedContent
                .background {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemBackground))
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.regularMaterial)
                            .overlay(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        Color.white.opacity(colorScheme == .light ? 0.42 : 0.10),
                                        lineWidth: 1
                                    )
                            }
                    }
                }
        }
    }

    private var decoratedContent: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        Color.primary.opacity(contrast == .increased ? 0.36 : 0.10),
                        lineWidth: contrast == .increased ? 2 : 1
                    )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .light ? Self.lightModeShadowOpacity : 0.18),
                radius: colorScheme == .light ? 12 : 8,
                y: colorScheme == .light ? 5 : 3
            )
    }
}
