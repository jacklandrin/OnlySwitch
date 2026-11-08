import AVKit
import ComposableArchitecture
import RemoteCore
import SwiftUI

/// The media area of the viewer: zoomable original (or thumbnail), the recording player once its
/// original is downloaded (the poster frame until then), progress and the offline hint.
struct RemoteScreenshotDetailContent: View {
    let store: StoreOf<RemoteScreenshotsFeature>
    let item: RemoteScreenshotItem
    @State private var image: UIImage?

    var body: some View {
        let originalURL = store.imageURLs[item.id]
        // A recording's original is a movie: only its thumbnail (the poster frame) is decoded.
        let displayURL = item.isRecording ? store.thumbnailURLs[item.id] : originalURL ?? store.thumbnailURLs[item.id]
        let isDownloading = store.state.isDownloading(item.id)
        ZStack {
            if item.isRecording, let originalURL {
                RemoteScreenshotVideoPlayer(url: originalURL)
            } else if let image {
                RemoteScreenshotZoomableImage(image: image, accessibilityLabel: accessibilityLabel)
                    .onDrag(dragProvider)
            } else if isDownloading == false {
                ContentUnavailableView("Screenshots & Record", systemImage: "photo", description: Text("No preview is available."))
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
                    message: item.isRecording
                        ? "Connect to the Mac to play this recording."
                        : "Connect to the Mac to view the full-size screenshot.",
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

    private var accessibilityLabel: Text { RemoteScreenshotCell.accessibilityLabel(for: item) }

    private func dragProvider() -> NSItemProvider {
        guard let macID = store.selectedMacID else { return NSItemProvider() }
        let provider = RemoteScreenshotDragProvider.itemProvider(macID: macID, item: item, cachedURL: store.imageURLs[item.id], images: store.dragImages.client)
        // Start the download now: on iPhone the drop target asks for the file after OnlyRemote has
        // left the foreground. The provider then joins the same single-flight load.
        store.send(.dragStarted(item.id))
        return provider
    }
}

/// Plays a downloaded recording. The player is created per file and paused when the viewer goes away.
struct RemoteScreenshotVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .task(id: url) {
                self.player?.pause()
                let player = AVPlayer(url: url)
                self.player = player
                player.play()
            }
            .onDisappear { player?.pause() }
    }
}
