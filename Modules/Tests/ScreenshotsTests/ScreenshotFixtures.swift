#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Screenshots

func item(id: UUID = UUID(), createdAt: TimeInterval, pinned: Bool = false, fileName: String? = nil) -> ScreenshotItem {
    ScreenshotItem(id: id, fileName: fileName ?? "Screenshot \(id.uuidString).png", createdAt: Date(timeIntervalSince1970: createdAt), isPinned: pinned)
}

/// Every test works inside its own temporary directory; nothing touches the user's Pictures folder or Trash.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("OnlySwitchScreenshotsTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func pngData(width: Int = 4, height: Int = 4, color: (CGFloat, CGFloat, CGFloat) = (1, 0, 0)) throws -> Data {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@discardableResult func writePNG(to url: URL, width: Int = 4, height: Int = 4, color: (CGFloat, CGFloat, CGFloat) = (1, 0, 0)) throws -> URL {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try pngData(width: width, height: height, color: color).write(to: url)
    return url
}

// Records only fixture URLs. No test invokes the user's Trash.
final class ScreenshotTrashRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    let failingName: String?
    init(failingName: String? = nil) { self.failingName = failingName }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
    func trash(_ url: URL) throws {
        if url.lastPathComponent == failingName { throw CocoaError(.fileWriteNoPermission) }
        lock.lock(); defer { lock.unlock() }; storage.append(url)
        try FileManager.default.removeItem(at: url)
    }
}
#endif
