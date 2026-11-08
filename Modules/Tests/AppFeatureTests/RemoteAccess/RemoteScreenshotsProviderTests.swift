import AVFoundation
import ComposableArchitecture
import CoreGraphics
import Foundation
import ImageIO
import RemoteCore
import Screenshots
import Testing
import UniformTypeIdentifiers
@testable import AppFeature

struct RemoteScreenshotsProviderTests {
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!

    @Test func remoteItemUsesFileSizeTypeAndSanitizedName() throws {
        let folder = try Self.temporaryFolder()
        let url = folder.appendingPathComponent("Screenshot 1.png")
        try Data(repeating: 1, count: 42).write(to: url)
        let item = ScreenshotItem(id: firstID, fileName: "Screenshot 1.png", createdAt: .init(timeIntervalSince1970: 5), isPinned: true, revision: 2)
        let remote = try #require(RemoteScreenshotsProvider.remoteItem(item, fileURL: url))
        #expect(remote == .init(id: firstID, fileName: "Screenshot 1.png", contentType: UTType.png.identifier, createdAt: .init(timeIntervalSince1970: 5), isPinned: true, revision: 2, byteCount: 42))
    }

    @Test func libraryStreamDeduplicatesAndSkipsUnresolvableItems() async throws {
        let folder = try Self.temporaryFolder()
        let url = folder.appendingPathComponent("a.png")
        try Data([1]).write(to: url)
        let unchangedItems = [
            ScreenshotItem(id: firstID, fileName: "a.png", createdAt: .init(timeIntervalSince1970: 1)),
            ScreenshotItem(id: secondID, fileName: "missing.png", createdAt: .init(timeIntervalSince1970: 2)),
        ]
        let changedItems = [
            ScreenshotItem(id: firstID, fileName: "a.png", createdAt: .init(timeIntervalSince1970: 1), revision: 1),
        ]
        // The first three polls see the same items; the fourth sees a changed revision.
        let pollCount = LockIsolated(0)
        let service = RemoteScreenshotsProvider.service(
            source: .init(
                items: {
                    let poll = pollCount.withValue { count in
                        count += 1
                        return count
                    }
                    return poll < 4 ? unchangedItems : changedItems
                },
                isCollectionEnabled: { true },
                itemsChanged: { _ in }
            ),
            client: Self.client(fileURLs: [firstID: url]),
            clock: ImmediateClock()
        )
        var libraries = service.libraries(false).makeAsyncIterator()

        let first = try #require(await libraries.next())
        #expect(first.revision == 1)
        #expect(first.items.map(\.id) == [firstID])
        #expect(first.isCollectionEnabled)

        // Unchanged polls publish nothing, so the next library is the changed fourth poll.
        let second = try #require(await libraries.next())
        #expect(second.revision == 2)
        #expect(second.items.map(\.revision) == [1])
        #expect(pollCount.value >= 4)
    }

    @Test func thumbnailsReportMissingIDsAndRespectSizeLimit() async throws {
        let folder = try Self.temporaryFolder()
        let url = folder.appendingPathComponent("a.png")
        try Self.pngData(width: 1200, height: 800).write(to: url)
        let items = [ScreenshotItem(id: firstID, fileName: "a.png", createdAt: .now)]
        let service = RemoteScreenshotsProvider.service(
            source: .init(items: { items }, isCollectionEnabled: { true }, itemsChanged: { _ in }),
            client: Self.client(fileURLs: [firstID: url])
        )
        let result = await service.thumbnails([firstID, secondID])
        #expect(result.thumbnails.map(\.itemID) == [firstID])
        #expect(result.thumbnails.allSatisfy { $0.jpegData.count <= RemoteScreenshotLimits.maximumThumbnailBytes })
        #expect(result.missingIDs == [secondID])
    }

    @Test func imageRejectsChangedRevisionAndUnknownItems() async throws {
        let folder = try Self.temporaryFolder()
        let url = folder.appendingPathComponent("a.png")
        try Data([9, 9]).write(to: url)
        let items = [ScreenshotItem(id: firstID, fileName: "a.png", createdAt: .now, revision: 3)]
        let service = RemoteScreenshotsProvider.service(
            source: .init(items: { items }, isCollectionEnabled: { true }, itemsChanged: { _ in }),
            client: Self.client(fileURLs: [firstID: url])
        )
        let image = try await service.image(firstID, 3, false)
        #expect(image.data == Data([9, 9]))
        #expect(image.contentType == UTType.png.identifier)
        await #expect(throws: RemoteProtocolError.self) { _ = try await service.image(firstID, 2, false) }
        await #expect(throws: RemoteProtocolError.self) { _ = try await service.image(secondID, 0, false) }
    }

    @Test func deleteTrashesAppliesItemsAndReturnsFailures() async throws {
        let applied = LockIsolated<[[ScreenshotItem]]>([])
        let trashed = LockIsolated<[[UUID]]>([])
        let remaining = [ScreenshotItem(id: secondID, fileName: "b.png", createdAt: .now)]
        let failedID = secondID
        var client = Self.client(fileURLs: [:])
        client.trash = { ids in
            trashed.withValue { $0.append(ids) }
            return (items: remaining, failures: [ScreenshotFailure(key: ScreenshotFailure.trashFailedKey, itemID: failedID)])
        }
        let service = RemoteScreenshotsProvider.service(
            source: .init(items: { [] }, isCollectionEnabled: { true }, itemsChanged: { items in applied.withValue { $0.append(items) } }),
            client: client
        )
        #expect(await service.delete([firstID, secondID]) == [secondID])
        #expect(trashed.value == [[firstID, secondID]])
        #expect(applied.value == [remaining])
    }

    @Test func recordingsAreHiddenFromPeersWithoutCapability() async throws {
        let service = try await Self.mixedService(imageID: firstID, movieID: secondID).service
        let legacy = try await Self.firstLibrary(service.libraries(false))
        #expect(legacy.items.map(\.fileName) == ["a.png"])
        let modern = try await Self.firstLibrary(service.libraries(true))
        #expect(modern.items.map(\.fileName) == ["a.png", "b.mov"])
        let recording = try #require(modern.items.first { $0.isRecording })
        #expect(recording.contentType == UTType.quickTimeMovie.identifier)
        #expect((recording.durationSeconds ?? 0) > 0)
    }

    @Test func recordingOriginalRequiresCapability() async throws {
        let service = try await Self.mixedService(imageID: firstID, movieID: secondID).service
        await #expect(throws: RemoteProtocolError.self) { _ = try await service.image(secondID, 0, false) }
        let original = try await service.image(secondID, 0, true)
        #expect(original.contentType == UTType.quickTimeMovie.identifier)
        #expect(original.data.isEmpty == false)
    }

    @Test func recordingThumbnailIsAPosterJPEG() async throws {
        let service = try await Self.mixedService(imageID: firstID, movieID: secondID).service
        let result = await service.thumbnails([secondID])
        #expect(result.thumbnails.map(\.itemID) == [secondID])
        #expect(result.missingIDs.isEmpty)
    }

    // MARK: - Helpers

    /// A png (`a.png`) and a QuickTime recording (`b.mov`) in a temporary library.
    static func mixedService(imageID: UUID, movieID: UUID) async throws -> (service: RemoteScreenshotsService, movie: URL) {
        let folder = try temporaryFolder()
        let image = folder.appendingPathComponent("a.png")
        try Data([1]).write(to: image)
        let movie = try await writeMovie(to: folder.appendingPathComponent("b.mov"))
        let items = [
            ScreenshotItem(id: imageID, fileName: "a.png", createdAt: .init(timeIntervalSince1970: 1)),
            ScreenshotItem(id: movieID, fileName: "b.mov", createdAt: .init(timeIntervalSince1970: 2)),
        ]
        let service = RemoteScreenshotsProvider.service(
            source: .init(items: { items }, isCollectionEnabled: { true }, itemsChanged: { _ in }),
            client: client(fileURLs: [imageID: image, movieID: movie]),
            pollInterval: .milliseconds(10)
        )
        return (service, movie)
    }

    private static func firstLibrary(_ libraries: AsyncStream<RemoteScreenshotLibrary>) async throws -> RemoteScreenshotLibrary {
        var iterator = libraries.makeAsyncIterator()
        return try #require(await iterator.next())
    }

    /// Mirrors the Screenshots package's test-only `writeMovie`: a tiny H.264 movie.
    @discardableResult static func writeMovie(to url: URL, frames: Int = 5) async throws -> URL {
        let writer = try AVAssetWriter(outputURL: url, fileType: url.pathExtension.lowercased() == "mp4" ? .mp4 : .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, []); memset(CVPixelBufferGetBaseAddress(pixels), 0x7F, CVPixelBufferGetDataSize(pixels)); CVPixelBufferUnlockBaseAddress(pixels, [])
            #expect(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }

    static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteScreenshotsProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func client(fileURLs: [UUID: URL]) -> ScreenshotsClient {
        var client = ScreenshotsClient.testValue
        client.fileURL = { fileURLs[$0] }
        client.thumbnail = { url, maxPixel, _ in
            if ScreenshotMediaType(fileName: url.lastPathComponent) == .recording {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
                return try? await generator.image(at: .zero).image
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ] as CFDictionary)
        }
        client.duration = { url in
            guard let duration = try? await AVURLAsset(url: url).load(.duration), duration.isNumeric else { return nil }
            return duration.seconds
        }
        return client
    }

    private static func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
