import ComposableArchitecture
import CoreGraphics
import Foundation
import ImageIO
import RemoteCore
import Screenshots
import UniformTypeIdentifiers

/// Bridges the session-retained Screenshots store and `ScreenshotsClient` to remote peers. File reads and
/// thumbnail encoding run off the main actor; only reading the item list and applying deletions touch it.
enum RemoteScreenshotsProvider {
    struct Source: Sendable {
        var items: @Sendable () async -> [ScreenshotItem]
        var isCollectionEnabled: @Sendable () async -> Bool
        var itemsChanged: @Sendable ([ScreenshotItem]) async -> Void
    }

    static let thumbnailQualities: [CGFloat] = [0.7, 0.5, 0.35, 0.2]

    static func service(source: Source, client: ScreenshotsClient, pollInterval: Duration = .seconds(1)) -> RemoteScreenshotsService {
        RemoteScreenshotsService(
            libraries: {
                AsyncStream { continuation in
                    let task = Task {
                        var lastItems: [ScreenshotItem]?
                        var lastEnabled: Bool?
                        var revision: UInt64 = 0
                        while Task.isCancelled == false {
                            let items = await source.items()
                            let enabled = await source.isCollectionEnabled()
                            if items != lastItems || enabled != lastEnabled {
                                var remote: [RemoteScreenshotItem] = []
                                for item in items.prefix(RemoteScreenshotLimits.maximumItems) {
                                    if let url = await client.fileURL(item.id), let mapped = remoteItem(item, fileURL: url) { remote.append(mapped) }
                                }
                                revision &+= 1
                                continuation.yield(.init(revision: revision, isCollectionEnabled: enabled, items: remote))
                                lastItems = items
                                lastEnabled = enabled
                            }
                            try? await Task.sleep(for: pollInterval)
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            thumbnails: { ids in
                let items = await source.items()
                var thumbnails: [RemoteScreenshotThumbnail] = []
                var missing: [UUID] = []
                for id in ids.prefix(RemoteScreenshotLimits.maximumThumbnailsPerRequest) {
                    guard Task.isCancelled == false,
                          let item = items.first(where: { $0.id == id }),
                          let url = await client.fileURL(id),
                          let image = await client.thumbnail(url, RemoteScreenshotLimits.maximumThumbnailPixel, item.revision),
                          let data = jpegThumbnail(image, maximumBytes: RemoteScreenshotLimits.maximumThumbnailBytes),
                          let thumbnail = try? RemoteScreenshotThumbnail(itemID: id, revision: item.revision, jpegData: data) else {
                        missing.append(id)
                        continue
                    }
                    thumbnails.append(thumbnail)
                }
                return (thumbnails, missing)
            },
            image: { itemID, revision async throws(RemoteProtocolError) in
                let items = await source.items()
                guard let item = items.first(where: { $0.id == itemID }), let url = await client.fileURL(itemID) else {
                    throw RemoteProtocolError(code: .controlNotFound, message: "The screenshot is no longer on the Mac")
                }
                guard item.revision == revision else {
                    throw RemoteProtocolError(code: .controlUnavailable, message: "The screenshot changed on the Mac")
                }
                guard let mapped = remoteItem(item, fileURL: url) else {
                    throw RemoteProtocolError(code: .executionFailed, message: "The screenshot could not be read")
                }
                guard mapped.byteCount <= RemoteScreenshotLimits.maximumImageBytes else {
                    throw RemoteProtocolError(code: .controlUnavailable, message: "The screenshot is too large to transfer")
                }
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.isEmpty == false,
                      data.count <= RemoteScreenshotLimits.maximumImageBytes else {
                    throw RemoteProtocolError(code: .executionFailed, message: "The screenshot could not be read")
                }
                return (mapped.contentType, data)
            },
            delete: { ids in
                let ids = Array(ids.prefix(RemoteScreenshotLimits.maximumDeleteCount))
                guard ids.isEmpty == false else { return [] }
                let result = await client.trash(ids)
                await source.itemsChanged(result.items)
                let failed = Set(result.failures.compactMap(\.itemID))
                return ids.filter(failed.contains)
            }
        )
    }

    /// nil when the recorded file is not an image or its size cannot be read.
    static func remoteItem(_ item: ScreenshotItem, fileURL: URL) -> RemoteScreenshotItem? {
        guard let type = UTType(filenameExtension: fileURL.pathExtension), type.conforms(to: .image),
              let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return RemoteScreenshotItem(
            id: item.id,
            fileName: item.fileName,
            contentType: type.identifier,
            createdAt: item.createdAt,
            isPinned: item.isPinned,
            revision: item.revision,
            byteCount: size
        )
    }

    /// Re-encodes at decreasing quality until the JPEG fits; nil if it never does.
    static func jpegThumbnail(_ image: CGImage, maximumBytes: Int) -> Data? {
        for quality in thumbnailQualities {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            if data.length <= maximumBytes { return data as Data }
        }
        return nil
    }
}

extension RemoteScreenshotsService {
    /// Reads and updates the shared Screenshots store, whose `ScreenshotsClient` dependency is the same
    /// `liveValue` instance, so library, thumbnail cache and manifest are shared with the Mac UI.
    @MainActor
    static var live: Self {
        let store = SettingsVM.shared.screenshotsStore
        return RemoteScreenshotsProvider.service(
            source: .init(
                items: { await MainActor.run { store.items } },
                isCollectionEnabled: { await MainActor.run { store.captureStatus == .active } },
                itemsChanged: { items in await MainActor.run { _ = store.send(.itemsChanged(items)) } }
            ),
            client: ScreenshotsClient.liveValue
        )
    }
}
