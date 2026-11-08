import RemoteCore
import SwiftUI

struct ControlTileIconView: View {
    let icon: RemoteControlDescriptor.Icon
    let isShortcut: Bool
    let tint: Color

    @State private var decodedImage: UIImage?

    var body: some View {
        Group {
            switch icon {
            case let .systemSymbol(name):
                Image(systemName: name)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint)
            case .png:
                if let decodedImage {
                    Image(uiImage: decodedImage)
                        .renderingMode(isShortcut ? .original : .template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(isShortcut ? .primary : tint)
                } else {
                    Image(systemName: "switch.2")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(width: ControlTileView.iconSize, height: ControlTileView.iconSize)
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
        .task(id: pngData) {
            decodedImage = pngData.flatMap(UIImage.init(data:))
        }
    }

    private var pngData: Data? {
        guard case let .png(data) = icon else { return nil }
        return data
    }
}
