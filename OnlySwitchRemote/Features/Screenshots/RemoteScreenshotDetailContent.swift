import ComposableArchitecture
import RemoteCore
import SwiftUI

/// The image area of the viewer: zoomable original (or thumbnail), progress and the offline hint.
struct RemoteScreenshotDetailContent: View {
    let store: StoreOf<RemoteScreenshotsFeature>
    let item: RemoteScreenshotItem
    @State private var image: UIImage?

    var body: some View {
        let originalURL = store.imageURLs[item.id]
        let displayURL = originalURL ?? store.thumbnailURLs[item.id]
        let isDownloading = store.state.isDownloading(item.id)
        ZStack {
            if let image {
                RemoteScreenshotZoomableImage(image: image, accessibilityLabel: accessibilityLabel)
                    .onDrag(dragProvider)
            } else if isDownloading == false {
                ContentUnavailableView("Screenshots", systemImage: "photo", description: Text("No preview is available."))
            }
            if isDownloading {
                ProgressView()
                    .controlSize(.large)
                    .padding(16)
                    .background(.thinMaterial, in: .rect(cornerRadius: 16))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            if originalURL == nil, store.isOffline {
                RemoteScreenshotsBanner(
                    message: "Connect to the Mac to view the full-size screenshot.",
                    systemImage: "wifi.slash"
                )
                .padding(16)
            }
        }
        .navigationTitle(Text(item.createdAt, format: RemoteScreenshotCell.dateFormat))
        .task(id: displayURL) {
            guard let displayURL else { return }
            let isOriginal = displayURL == originalURL
            let decoded = await RemoteScreenshotImageDecoder.image(
                at: displayURL,
                maxPixelSize: isOriginal ? RemoteScreenshotImageDecoder.detailPixelSize : RemoteScreenshotImageDecoder.thumbnailPixelSize
            )
            if let decoded { image = decoded }
        }
    }

    private var accessibilityLabel: Text {
        let date = item.createdAt.formatted(RemoteScreenshotCell.dateFormat)
        return item.isPinned ? Text("Pinned screenshot, \(date)") : Text("Screenshot, \(date)")
    }

    private func dragProvider() -> NSItemProvider {
        guard let macID = store.selectedMacID else { return NSItemProvider() }
        let provider = RemoteScreenshotDragProvider.itemProvider(macID: macID, item: item, cachedURL: store.imageURLs[item.id], images: store.dragImages.client)
        // Start the download now: on iPhone the drop target asks for the file after OnlyRemote has
        // left the foreground. The provider then joins the same single-flight load.
        store.send(.dragStarted(item.id))
        return provider
    }
}
