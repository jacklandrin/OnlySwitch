import ComposableArchitecture
import CoreGraphics
import Foundation
import ImageIO
import RemoteCore
import Screenshots
import Testing
import UniformTypeIdentifiers
@testable import OnlySwitch

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
        let items = [
            ScreenshotItem(id: firstID, fileName: "a.png", createdAt: .init(timeIntervalSince1970: 1)),
            ScreenshotItem(id: secondID, fileName: "missing.png", createdAt: .init(timeIntervalSince1970: 2)),
        ]
        let service = RemoteScreenshotsProvider.service(
            source: .init(items: { items }, isCollectionEnabled: { true }, itemsChanged: { _ in }),
            client: Self.client(fileURLs: [firstID: url]),
            pollInterval: .milliseconds(10)
        )
        let received = LockIsolated<[RemoteScreenshotLibrary]>([])
        let consumer = Task {
            for await library in service.libraries() { received.withValue { $0.append(library) } }
        }
        // Unchanged items do not produce another library within several polls.
        try await Task.sleep(for: .milliseconds(150))
        consumer.cancel()
        let libraries = received.value
        #expect(libraries.count == 1)
        let library = try #require(libraries.first)
        #expect(library.items.map(\.id) == [firstID])
        #expect(library.isCollectionEnabled)
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
        let image = try await service.image(firstID, 3)
        #expect(image.data == Data([9, 9]))
        #expect(image.contentType == UTType.png.identifier)
        await #expect(throws: RemoteProtocolError.self) { _ = try await service.image(firstID, 2) }
        await #expect(throws: RemoteProtocolError.self) { _ = try await service.image(secondID, 0) }
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

    // MARK: - Helpers

    private static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteScreenshotsProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func client(fileURLs: [UUID: URL]) -> ScreenshotsClient {
        var client = ScreenshotsClient.testValue
        client.fileURL = { fileURLs[$0] }
        client.thumbnail = { url, maxPixel, _ in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ] as CFDictionary)
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
