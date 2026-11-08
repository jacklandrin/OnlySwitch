#if os(macOS)
import CoreGraphics
import Dependencies
import Foundation
import Observation

/// Holds one cell's decoded thumbnail and, for a recording, its duration. Loading goes through
/// `ScreenshotsClient.thumbnail` (cached by path, revision and size) and `ScreenshotsClient.duration`.
@MainActor
@Observable
final class ScreenshotThumbnailModel {
    private(set) var image: CGImage?
    private(set) var duration: Double?
    @ObservationIgnored @Dependency(\.screenshotsClient) private var client

    func load(_ request: ScreenshotThumbnailRequest) async {
        guard let url = request.url else { return }
        let loaded = await client.thumbnail(url, request.maxPixel, request.revision)
        guard !Task.isCancelled else { return }
        image = loaded
        let seconds = request.isRecording ? await client.duration(url) : nil
        guard !Task.isCancelled else { return }
        duration = seconds
    }
}

/// `.task(id:)` key: reload when the resolved file, the edit revision or the requested size changes.
struct ScreenshotThumbnailRequest: Equatable {
    var url: URL?
    var revision: Int
    var maxPixel: Int
    var isRecording: Bool
}
#endif
