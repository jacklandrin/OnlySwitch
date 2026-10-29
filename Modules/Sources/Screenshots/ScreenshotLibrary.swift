#if os(macOS)
import Foundation
import UniformTypeIdentifiers

/// Owns the persisted manifest of captures. Files are addressed only by recorded item id; callers never
/// supply a path that is trashed or overwritten, and every recorded name is re-validated before use.
public actor ScreenshotLibrary {
    private let folder: URL
    private let manifestURL: URL
    private let trashItem: @Sendable (URL) throws -> Void
    private let now: @Sendable () -> Date
    private let uuid: @Sendable () -> UUID
    /// nil until the manifest has been read, so every entry point reconciles with what is on disk first.
    private var items: [ScreenshotItem]?

    public init(folder: URL, manifestURL: URL, trash: @escaping @Sendable (URL) throws -> Void, now: @escaping @Sendable () -> Date, uuid: @escaping @Sendable () -> UUID) {
        self.folder = folder.standardizedFileURL; self.manifestURL = manifestURL; self.trashItem = trash; self.now = now; self.uuid = uuid
    }

    /// Re-reads the manifest, reconciles it with disk and adopts visible image files directly in the folder that
    /// are not recorded yet (e.g. captured while OnlySwitch was not running), dated by creation/modification date.
    public func load() throws -> [ScreenshotItem] {
        items = nil
        var list = try current()
        let recorded = Set(list.map(\.fileName))
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        let adopted: [ScreenshotItem] = names.compactMap { name in
            guard !recorded.contains(name), Self.isImageName(name), let url = validatedURL(for: name), isRegularFile(url) else { return nil }
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            return ScreenshotItem(id: uuid(), fileName: name, createdAt: values?.creationDate ?? values?.contentModificationDate ?? now())
        }
        if !adopted.isEmpty { list += adopted; try save(list) }
        return list.displayOrdered()
    }

    /// Records a new capture in the library folder. Returns nil for anything that is not a visible, regular
    /// image file directly inside the folder; returns the existing item when the name is already recorded.
    public func add(fileURL: URL) throws -> ScreenshotItem? {
        let name = fileURL.lastPathComponent
        guard let url = validatedURL(for: name), url == fileURL.standardizedFileURL, Self.isImageName(name), isRegularFile(url) else { return nil }
        var list = try current()
        if let existing = list.first(where: { $0.fileName == name }) { return existing }
        let item = ScreenshotItem(id: uuid(), fileName: name, createdAt: now())
        list.append(item)
        try save(list)
        return item
    }

    public func setPinned(_ id: UUID, _ isPinned: Bool) throws -> [ScreenshotItem] {
        var list = try current()
        guard let index = list.firstIndex(where: { $0.id == id }) else { throw ScreenshotFailure(key: ScreenshotFailure.notFoundKey, itemID: id) }
        list[index].isPinned = isPinned
        try save(list)
        return list.displayOrdered()
    }

    /// Moves recorded files to the Trash. A record is removed only when its file is gone; unknown ids and
    /// trash errors are reported per item and never turn into a path operation.
    public func trash(_ ids: [UUID]) -> ([ScreenshotItem], [ScreenshotFailure]) {
        var list: [ScreenshotItem]
        do { list = try current() } catch { return ((items ?? []).displayOrdered(), ids.map { ScreenshotFailure(key: ScreenshotFailure.libraryFailedKey, itemID: $0) }) }
        var failures: [ScreenshotFailure] = []
        for id in ids {
            guard let index = list.firstIndex(where: { $0.id == id }), let url = validatedURL(for: list[index].fileName) else {
                failures.append(.init(key: ScreenshotFailure.trashFailedKey, itemID: id)); continue
            }
            do {
                if FileManager.default.fileExists(atPath: url.path) || isSymbolicLink(url) { try trashItem(url) }
                list.remove(at: index)
            } catch { failures.append(.init(key: ScreenshotFailure.trashFailedKey, itemID: id)) }
        }
        do { try save(list) } catch { failures.append(.init(key: ScreenshotFailure.libraryFailedKey)) }
        return (list.displayOrdered(), failures)
    }

    /// Overwrites a recorded file with already-encoded image data via a hidden sibling temp file and an
    /// atomic `replaceItemAt`, then bumps the item's revision.
    public func replaceImage(_ id: UUID, data: Data) throws -> [ScreenshotItem] {
        var list = try current()
        guard let index = list.firstIndex(where: { $0.id == id }), let url = validatedURL(for: list[index].fileName), isRegularFile(url) else {
            throw ScreenshotFailure(key: ScreenshotFailure.notFoundKey, itemID: id)
        }
        let temporary = folder.appendingPathComponent(".onlyswitch-edit-\(uuid().uuidString).\(url.pathExtension)")
        do {
            try data.write(to: temporary)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw ScreenshotFailure(key: ScreenshotFailure.libraryFailedKey, itemID: id)
        }
        list[index].revision += 1
        try save(list)
        return list.displayOrdered()
    }

    /// The recorded file, only while it is still a regular file (never a symbolic link swapped in later).
    public func fileURL(_ id: UUID) -> URL? {
        guard let name = (try? current())?.first(where: { $0.id == id })?.fileName, let url = validatedURL(for: name), isRegularFile(url) else { return nil }
        return url
    }

    // MARK: - Private

    private func current() throws -> [ScreenshotItem] {
        if let items { return items }
        var decoded: [ScreenshotItem] = []
        var dirty = false
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            if let data = try? Data(contentsOf: manifestURL), let list = try? JSONDecoder().decode([ScreenshotItem].self, from: data) { decoded = list } else { dirty = true }
        }
        var seen = Set<String>()
        let reconciled = decoded.filter { entry in
            guard let url = validatedURL(for: entry.fileName), Self.isImageName(entry.fileName), isRegularFile(url), seen.insert(entry.fileName).inserted else { return false }
            return true
        }
        if reconciled.count != decoded.count { dirty = true }
        if dirty { try save(reconciled) } else { items = reconciled }
        return reconciled
    }

    private func save(_ list: [ScreenshotItem]) throws {
        do {
            try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(list).write(to: manifestURL, options: .atomic)
        } catch { throw ScreenshotFailure(key: ScreenshotFailure.libraryFailedKey) }
        items = list
    }

    /// A recorded name must be a single, non-hidden path component whose standardized parent is the folder.
    private func validatedURL(for fileName: String) -> URL? {
        guard !fileName.isEmpty, !fileName.contains("/"), fileName != "..", fileName != ".", !fileName.hasPrefix(".") else { return nil }
        let url = folder.appendingPathComponent(fileName).standardizedFileURL
        guard url.deletingLastPathComponent().standardizedFileURL.path == folder.path else { return nil }
        return url
    }

    private func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true
    }

    private func isSymbolicLink(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true }

    static func isImageName(_ name: String) -> Bool {
        guard !name.hasPrefix("."), let type = UTType(filenameExtension: (name as NSString).pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}
#endif
