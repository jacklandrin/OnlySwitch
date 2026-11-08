import Foundation
import RemoteCore
import Testing
@testable import OnlySwitchRemote

struct RemoteScreenshotCacheClientTests {
    private let macID = UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!
    private let otherMacID = UUID(uuidString: "00000000-0000-0000-0000-00000000D002")!

    private func item(_ n: Int, revision: Int = 0, name: String = "Shot.png") -> RemoteScreenshotItem {
        .init(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!, fileName: name, contentType: "public.png", createdAt: .init(timeIntervalSince1970: Double(n)), isPinned: false, revision: revision, byteCount: 3)
    }

    @Test func savesAndReloadsLibraryThumbnailsAndImages() async throws {
        let cache = RemoteScreenshotCacheClient.live(root: try Self.root())
        let first = item(1)
        let library = RemoteScreenshotLibrary(revision: 1, isCollectionEnabled: true, items: [first])
        _ = await cache.replaceLibrary(macID, library)
        let thumbnailURLs = await cache.saveThumbnails(macID, [try .init(itemID: first.id, revision: 0, jpegData: Data([1]))])
        let imageURL = try await cache.saveImage(macID, first, try Self.transferFile(Data([1, 2, 3])))
        #expect(imageURL.lastPathComponent == "Shot.png")
        #expect(try Data(contentsOf: imageURL) == Data([1, 2, 3]))

        let loaded = try #require(await cache.load(macID))
        #expect(loaded.library == library)
        #expect(loaded.thumbnailURLs == thumbnailURLs)
        #expect(loaded.imageURLs == [first.id: imageURL])
        #expect(await cache.load(otherMacID) == nil)
    }

    @Test func savingMovesTheTransferFileIntoPlaceReplacingAnyExistingOne() async throws {
        let root = try Self.root()
        let cache = RemoteScreenshotCacheClient.live(root: root)
        let first = item(1)
        _ = await cache.replaceLibrary(macID, .init(revision: 1, isCollectionEnabled: true, items: [first]))
        _ = try await cache.saveImage(macID, first, try Self.transferFile(Data([1])))
        let transfer = try Self.transferFile(Data([4, 5, 6]))

        let url = try await cache.saveImage(macID, first, transfer)

        let expected = root
            .appendingPathComponent(macID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("images/\(first.cacheKey)/Shot.png")
            .standardizedFileURL
        #expect(url == expected)
        #expect(try Data(contentsOf: url) == Data([4, 5, 6]))
        #expect(FileManager.default.fileExists(atPath: transfer.path) == false)
        #expect(await cache.imageURL(macID, first) == url)
    }

    @Test func newRevisionAndRemovedItemsArePruned() async throws {
        let cache = RemoteScreenshotCacheClient.live(root: try Self.root())
        let first = item(1), second = item(2)
        _ = await cache.replaceLibrary(macID, .init(revision: 1, isCollectionEnabled: true, items: [first, second]))
        _ = await cache.saveThumbnails(macID, [try .init(itemID: first.id, revision: 0, jpegData: Data([1])), try .init(itemID: second.id, revision: 0, jpegData: Data([2]))])
        let oldImage = try await cache.saveImage(macID, first, try Self.transferFile(Data([9])))

        let edited = item(1, revision: 1)
        let snapshot = await cache.replaceLibrary(macID, .init(revision: 2, isCollectionEnabled: true, items: [edited]))
        #expect(snapshot.thumbnailURLs.isEmpty)
        #expect(snapshot.imageURLs.isEmpty)
        #expect(FileManager.default.fileExists(atPath: oldImage.path) == false)
        #expect(await cache.imageURL(macID, edited) == nil)
    }

    @Test func thumbnailsForUnlistedItemsOrStaleRevisionsAreIgnored() async throws {
        let cache = RemoteScreenshotCacheClient.live(root: try Self.root())
        let first = item(1, revision: 2)
        _ = await cache.replaceLibrary(macID, .init(revision: 1, isCollectionEnabled: true, items: [first]))
        let saved = await cache.saveThumbnails(macID, [
            try .init(itemID: first.id, revision: 1, jpegData: Data([1])),
            try .init(itemID: UUID(), revision: 0, jpegData: Data([2])),
        ])
        #expect(saved.isEmpty)
    }

    @Test func removeMacDeletesEverything() async throws {
        let cache = RemoteScreenshotCacheClient.live(root: try Self.root())
        _ = await cache.replaceLibrary(macID, .init(revision: 1, isCollectionEnabled: true, items: [item(1)]))
        await cache.removeMac(macID)
        #expect(await cache.load(macID) == nil)
    }

    @Test func removeMacKeepsOtherMacs() async throws {
        let cache = RemoteScreenshotCacheClient.live(root: try Self.root())
        let library = RemoteScreenshotLibrary(revision: 1, isCollectionEnabled: true, items: [item(1)])
        _ = await cache.replaceLibrary(macID, library)
        _ = await cache.replaceLibrary(otherMacID, library)
        await cache.removeMac(macID)
        #expect(await cache.load(otherMacID)?.library == library)
    }

    @Test func corruptIndexLoadsAsEmpty() async throws {
        let root = try Self.root()
        let cache = RemoteScreenshotCacheClient.live(root: root)
        let folder = root.appendingPathComponent(macID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: folder.appendingPathComponent("library.json"))
        #expect(await cache.load(macID) == nil)
    }

    @Test(arguments: ["../../escape.png", "..", "/etc/passwd", "a/../../b.png", ".hidden", "   "])
    func hostileFileNamesStayInsideTheMacFolder(_ name: String) async throws {
        let root = try Self.root()
        let cache = RemoteScreenshotCacheClient.live(root: root)
        let hostile = item(1, name: name)
        _ = await cache.replaceLibrary(macID, .init(revision: 1, isCollectionEnabled: true, items: [hostile]))
        let url = try await cache.saveImage(macID, hostile, try Self.transferFile(Data([1])))
        let imagesFolder = root
            .appendingPathComponent(macID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(hostile.cacheKey, isDirectory: true)
            .standardizedFileURL
        #expect(url.standardizedFileURL.deletingLastPathComponent().path == imagesFolder.path)
        #expect(url.lastPathComponent.contains("/") == false)
        #expect(url.lastPathComponent.hasPrefix(".") == false)
        #expect(await cache.imageURL(macID, hostile) == url)
    }

    private static func transferFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transfer-\(UUID().uuidString)")
        try data.write(to: url)
        return url
    }

    private static func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteScreenshotCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
