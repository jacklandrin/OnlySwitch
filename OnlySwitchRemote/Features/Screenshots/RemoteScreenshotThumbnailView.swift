import SwiftUI

/// A cached thumbnail file, decoded off the main actor, with a placeholder while it is missing.
struct RemoteScreenshotThumbnailView: View {
    let url: URL?
    let isLoading: Bool
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: url) {
                guard let url else {
                    image = nil
                    return
                }
                image = await RemoteScreenshotImageDecoder.image(
                    at: url,
                    maxPixelSize: RemoteScreenshotImageDecoder.thumbnailPixelSize
                )
            }
    }
}
