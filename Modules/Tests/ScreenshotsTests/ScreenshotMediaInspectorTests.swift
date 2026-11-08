#if os(macOS)
import Foundation
import Testing
@testable import Screenshots

struct ScreenshotMediaInspectorTests {
    @Test func posterFrameAndDurationForRecording() async throws {
        let url = try await writeMovie(to: makeTemporaryDirectory().appendingPathComponent("r.mov"), frames: 10)
        let image = try #require(await ScreenshotMediaInspector.posterFrame(url, maxPixel: 64))
        #expect(image.width == 16)
        let duration = try #require(await ScreenshotMediaInspector.duration(url))
        #expect(abs(duration - 0.9) < 0.15)
    }

    @Test func cacheThumbnailsImagesAndRecordings() async throws {
        let dir = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let png = try writePNG(to: dir.appendingPathComponent("a.png"), width: 40, height: 20)
        let mov = try await writeMovie(to: dir.appendingPathComponent("b.mov"))
        let cache = ScreenshotThumbnailCache()
        #expect(await cache.thumbnail(for: png, maxPixel: 20, revision: 0)?.width == 20)
        #expect(await cache.thumbnail(for: mov, maxPixel: 64, revision: 0) != nil)
        #expect(await ScreenshotMediaInspector.duration(png) == nil)
    }
}
#endif
