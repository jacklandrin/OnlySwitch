import Dependencies
import Foundation
import RemoteCore

struct RemoteScreenshotCacheSnapshot: Equatable, Sendable {
    var library: RemoteScreenshotLibrary
    var thumbnailURLs: [UUID: URL]
    var imageURLs: [UUID: URL]
}

enum RemoteScreenshotCacheError: Swift.Error, Equatable, Sendable {
    case pathOutsideCache
}

/// Per-Mac file cache under Caches (never backed up).
///
/// Layout: `<root>/<macID>/library.json`, `thumbnails/<cacheKey>.jpg`, `images/<cacheKey>/<fileName>`.
/// Paths are derived only from the Mac id, each item's cache key (UUID + revision) and its sanitized
/// file name, and every resolved path is checked to stay inside the Mac's folder.
struct RemoteScreenshotCacheClient: Sendable {
    var load: @Sendable (_ macID: UUID) async -> RemoteScreenshotCacheSnapshot?
    /// Saves the index and prunes files for items/revisions no longer listed; returns what is still cached.
    var replaceLibrary: @Sendable (_ macID: UUID, RemoteScreenshotLibrary) async -> RemoteScreenshotCacheSnapshot
    /// Saves only thumbnails whose item and revision are in the cached library.
    var saveThumbnails: @Sendable (_ macID: UUID, [RemoteScreenshotThumbnail]) async -> [UUID: URL]
    var imageURL: @Sendable (_ macID: UUID, RemoteScreenshotItem) async -> URL?
    var saveImage: @Sendable (_ macID: UUID, RemoteScreenshotItem, Data) async throws -> URL
    var removeMac: @Sendable (_ macID: UUID) async -> Void

    static func live(root: URL) -> Self {
        let store = RemoteScreenshotFileStore(root: root)
        return Self(
            load: { await store.load($0) },
            replaceLibrary: { await store.replaceLibrary($0, $1) },
            saveThumbnails: { await store.saveThumbnails($0, $1) },
            imageURL: { await store.imageURL($0, $1) },
            saveImage: { try await store.saveImage($0, $1, $2) },
            removeMac: { await store.removeMac($0) }
        )
    }

    static var live: Self {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return live(root: caches.appendingPathComponent("OnlyRemote/Screenshots", isDirectory: true))
    }

    static let noop = Self(
        load: { _ in nil },
        replaceLibrary: { _, library in .init(library: library, thumbnailURLs: [:], imageURLs: [:]) },
        saveThumbnails: { _, _ in [:] },
        imageURL: { _, _ in nil },
        saveImage: { _, _, _ in throw RemoteDependencyError.unimplemented },
        removeMac: { _ in }
    )
}

extension RemoteScreenshotCacheClient: DependencyKey {
    static var liveValue: Self { .live }
    static var testValue: Self { .noop }
}

extension DependencyValues {
    var remoteScreenshotCache: RemoteScreenshotCacheClient {
        get { self[RemoteScreenshotCacheClient.self] }
        set { self[RemoteScreenshotCacheClient.self] = newValue }
    }
}

private actor RemoteScreenshotFileStore {
    private let root: URL
    private let fileManager = FileManager.default

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func load(_ macID: UUID) -> RemoteScreenshotCacheSnapshot? {
        guard let data = try? Data(contentsOf: indexURL(macID)),
              let library = try? JSONDecoder().decode(RemoteScreenshotLibrary.self, from: data) else { return nil }
        return snapshot(macID, library)
    }

    func replaceLibrary(_ macID: UUID, _ library: RemoteScreenshotLibrary) -> RemoteScreenshotCacheSnapshot {
        try? fileManager.createDirectory(at: macFolder(macID), withIntermediateDirectories: true)
        try? JSONEncoder().encode(library).write(to: indexURL(macID), options: .atomic)
        let keys = Set(library.items.map(\.cacheKey))
        prune(thumbnailsFolder(macID), keeping: Set(keys.map { "\($0).jpg" }))
        prune(imagesFolder(macID), keeping: keys)
        return snapshot(macID, library)
    }

    func saveThumbnails(_ macID: UUID, _ thumbnails: [RemoteScreenshotThumbnail]) -> [UUID: URL] {
        guard let data = try? Data(contentsOf: indexURL(macID)),
              let library = try? JSONDecoder().decode(RemoteScreenshotLibrary.self, from: data) else { return [:] }
        try? fileManager.createDirectory(at: thumbnailsFolder(macID), withIntermediateDirectories: true)
        var saved: [UUID: URL] = [:]
        for thumbnail in thumbnails {
            guard let item = library.items.first(where: { $0.id == thumbnail.itemID && $0.revision == thumbnail.revision }),
                  let url = thumbnailURL(macID, item) else { continue }
            if (try? thumbnail.jpegData.write(to: url, options: .atomic)) != nil { saved[item.id] = url }
        }
        return saved
    }

    func imageURL(_ macID: UUID, _ item: RemoteScreenshotItem) -> URL? {
        guard let url = imageFileURL(macID, item), fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func saveImage(_ macID: UUID, _ item: RemoteScreenshotItem, _ data: Data) throws -> URL {
        guard let url = imageFileURL(macID, item) else { throw RemoteScreenshotCacheError.pathOutsideCache }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    func removeMac(_ macID: UUID) {
        try? fileManager.removeItem(at: macFolder(macID))
    }

    private func snapshot(_ macID: UUID, _ library: RemoteScreenshotLibrary) -> RemoteScreenshotCacheSnapshot {
        var thumbnails: [UUID: URL] = [:]
        var images: [UUID: URL] = [:]
        for item in library.items {
            if let thumbnail = thumbnailURL(macID, item), fileManager.fileExists(atPath: thumbnail.path) {
                thumbnails[item.id] = thumbnail
            }
            if let image = imageURL(macID, item) { images[item.id] = image }
        }
        return .init(library: library, thumbnailURLs: thumbnails, imageURLs: images)
    }

    private func prune(_ folder: URL, keeping names: Set<String>) {
        for name in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] where names.contains(name) == false {
            try? fileManager.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private func macFolder(_ macID: UUID) -> URL {
        root.appendingPathComponent(macID.uuidString.lowercased(), isDirectory: true)
    }

    private func indexURL(_ macID: UUID) -> URL {
        macFolder(macID).appendingPathComponent("library.json")
    }

    private func thumbnailsFolder(_ macID: UUID) -> URL {
        macFolder(macID).appendingPathComponent("thumbnails", isDirectory: true)
    }

    private func imagesFolder(_ macID: UUID) -> URL {
        macFolder(macID).appendingPathComponent("images", isDirectory: true)
    }

    private func thumbnailURL(_ macID: UUID, _ item: RemoteScreenshotItem) -> URL? {
        contained(thumbnailsFolder(macID).appendingPathComponent("\(item.cacheKey).jpg"), in: macID)
    }

    /// `images/<cacheKey>/<sanitized file name>` so drag and copy keep the Mac's file name.
    private func imageFileURL(_ macID: UUID, _ item: RemoteScreenshotItem) -> URL? {
        // `RemoteScreenshotItem` already sanitizes; re-sanitizing keeps this safe for any future initializer.
        let fileName = RemoteScreenshotItem.sanitizedFileName(item.fileName)
        let url = imagesFolder(macID)
            .appendingPathComponent(item.cacheKey, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        return contained(url, in: macID)
    }

    /// Returns the URL only when it resolves strictly inside the Mac's folder.
    private func contained(_ url: URL, in macID: UUID) -> URL? {
        let folder = macFolder(macID).standardizedFileURL.path
        let resolved = url.standardizedFileURL
        guard resolved.path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/") else { return nil }
        return resolved
    }
}
