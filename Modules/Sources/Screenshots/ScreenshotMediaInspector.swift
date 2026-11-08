#if os(macOS)
import AVFoundation
import CoreGraphics

/// Reads recordings with AVFoundation: a poster frame (first frame, orientation applied) and the duration.
/// Both return nil for anything AVFoundation cannot read, including images.
enum ScreenshotMediaInspector {
    static func posterFrame(_ url: URL, maxPixel: Int) async -> CGImage? {
        guard ScreenshotMediaType(fileName: url.lastPathComponent) == .recording else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: max(1, maxPixel), height: max(1, maxPixel))
        return try? await generator.image(at: .zero).image
    }

    static func duration(_ url: URL) async -> Double? {
        guard ScreenshotMediaType(fileName: url.lastPathComponent) == .recording,
              let duration = try? await AVURLAsset(url: url).load(.duration), duration.isNumeric else { return nil }
        return duration.seconds
    }
}
#endif
