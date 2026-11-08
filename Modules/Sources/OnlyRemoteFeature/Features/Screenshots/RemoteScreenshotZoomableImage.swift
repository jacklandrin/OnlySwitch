import SwiftUI

/// Pinch or double-tap to zoom, pan while zoomed. Zoom is view-local presentation state.
struct RemoteScreenshotZoomableImage: View {
    let image: UIImage
    let accessibilityLabel: Text
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let zoomRange: ClosedRange<CGFloat> = 1...5

    var body: some View {
        GeometryReader { proxy in
            let scale = Self.clamped(zoom * pinch)
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width * scale, height: proxy.size.height * scale)
            }
            .scrollDisabled(scale <= 1)
            .defaultScrollAnchor(.center)
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = Self.clamped(zoom * value.magnification) }
            )
            // A tap count is needed here, so this cannot be a Button.
            .onTapGesture(count: 2, perform: toggleZoom)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isImage)
        .accessibilityZoomAction { action in
            switch action.direction {
            case .zoomIn: zoom = Self.clamped(zoom * 2)
            case .zoomOut: zoom = Self.clamped(zoom / 2)
            @unknown default: break
            }
        }
    }

    private func toggleZoom() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            zoom = zoom > 1 ? 1 : 2.5
        }
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
    }
}
