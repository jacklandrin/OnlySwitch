import Dependencies
import Foundation
import RemoteCore
import Testing
import UniformTypeIdentifiers
@testable import OnlySwitchRemote

struct RemoteScreenshotDragProviderTests {
    private let macID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!

    private func item(contentType: String = "public.png", fileName: String = "Shot.png") -> RemoteScreenshotItem {
        RemoteScreenshotItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!,
            fileName: fileName,
            contentType: contentType,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            isPinned: false,
            revision: 2,
            byteCount: 3
        )
    }

    private func temporaryFile(named name: String, contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteScreenshotDragProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    private func loadFile(_ provider: NSItemProvider, type: UTType) async throws -> (name: String, data: Data) {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                if let url, let data = try? Data(contentsOf: url) {
                    continuation.resume(returning: (url.lastPathComponent, data))
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    @Test func registersTheOriginalTypeAndLoadsLazilyThroughTheImageClient() async throws {
        let source = try temporaryFile(named: "Shot.png", contents: Data([1, 2, 3]))
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let loads = LockIsolated<[UUID]>([])
        let expectedMac = macID
        let images = RemoteScreenshotImageClient { mac, item in
            #expect(mac == expectedMac)
            loads.withValue { $0.append(item.id) }
            return source
        }
        let provider = RemoteScreenshotDragProvider.itemProvider(macID: macID, item: item(), cachedURL: nil, images: images)
        #expect(provider.registeredTypeIdentifiers == [UTType.png.identifier])
        #expect(provider.suggestedName == "Shot")
        #expect(loads.value.isEmpty)

        let file = try await loadFile(provider, type: .png)
        #expect(file.data == Data([1, 2, 3]))
        #expect(loads.value == [item().id])
    }

    @Test func usesAnExistingCachedOriginalWithoutLoading() async throws {
        let cached = try temporaryFile(named: "Shot.png", contents: Data([4, 5]))
        defer { try? FileManager.default.removeItem(at: cached.deletingLastPathComponent()) }
        let images = RemoteScreenshotImageClient { _, _ in
            Issue.record("A cached original must not be downloaded")
            throw CancellationError()
        }
        let provider = RemoteScreenshotDragProvider.itemProvider(macID: macID, item: item(), cachedURL: cached, images: images)
        let file = try await loadFile(provider, type: .png)
        #expect(file.data == Data([4, 5]))
    }

    @Test func handsOutACopyNamedAfterTheScreenshotWhenTheFileNameDiffers() async throws {
        let cached = try temporaryFile(named: "cache-entry", contents: Data([6]))
        defer { try? FileManager.default.removeItem(at: cached.deletingLastPathComponent()) }
        let images = RemoteScreenshotImageClient { _, _ in cached }
        let provider = RemoteScreenshotDragProvider.itemProvider(macID: macID, item: item(fileName: "Named.png"), cachedURL: nil, images: images)
        let file = try await loadFile(provider, type: .png)
        #expect(file.data == Data([6]))
        #expect(file.name.hasSuffix(".png"))
        #expect(FileManager.default.fileExists(atPath: cached.path))
    }

    @Test func recordingsRegisterTheirMovieType() {
        let images = RemoteScreenshotImageClient { _, _ in throw CancellationError() }
        let provider = RemoteScreenshotDragProvider.itemProvider(macID: macID, item: item(contentType: "com.apple.quicktime-movie", fileName: "clip.mov"), cachedURL: nil, images: images)
        #expect(provider.registeredTypeIdentifiers == [UTType.quickTimeMovie.identifier])
    }

    @Test func nonImageTypesFallBackToGenericImageAndFailuresReachTheDropTarget() async throws {
        let images = RemoteScreenshotImageClient { _, _ in throw RemoteProtocolError(code: .controlNotFound, message: "gone") }
        let provider = RemoteScreenshotDragProvider.itemProvider(macID: macID, item: item(contentType: "public.plain-text"), cachedURL: nil, images: images)
        #expect(provider.registeredTypeIdentifiers == [UTType.image.identifier])
        await #expect(throws: (any Error).self) { try await loadFile(provider, type: .image) }
    }
}
