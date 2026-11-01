import Foundation
import ImageIO
import UIKit

/// Decodes cached screenshot files off the main actor, downsampled to the size they are shown at.
enum RemoteScreenshotImageDecoder {
    static let thumbnailPixelSize = 600
    static let detailPixelSize = 4_096

    static func image(at url: URL, maxPixelSize: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            decode(url, maxPixelSize: maxPixelSize)
        }.value
    }

    private static func decode(_ url: URL, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image)
    }
}
