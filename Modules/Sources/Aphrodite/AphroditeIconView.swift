#if os(macOS)
import AppKit
import SwiftUI

public enum AphroditeIconRenderer {
    public static func image(svg: String?) -> NSImage? {
        guard let svg, let validated = AphroditeSVGValidator.validated(svg) else { return nil }
        return NSImage(data: Data(validated.utf8))
    }
}

@available(macOS 26.0, *)
public struct AphroditeIconView: View {
    private let svg: String?
    private let fallbackSystemImage: String

    public init(svg: String?, fallbackSystemImage: String = "star.hexagon") {
        self.svg = svg
        self.fallbackSystemImage = fallbackSystemImage
    }

    public var body: some View {
        Group {
            if let image = AphroditeIconRenderer.image(svg: svg) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: fallbackSystemImage).resizable().scaledToFit().padding(3)
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
