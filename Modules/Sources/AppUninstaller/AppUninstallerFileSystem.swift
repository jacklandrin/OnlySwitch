#if os(macOS)
import Foundation

/// Authorization is session-only and uses immutable file identities, never caller-supplied paths.
actor AppUninstallerFileSystem {
    private struct Identity: Equatable, Sendable { var device: UInt64; var inode: UInt64 }
    private struct Candidate: Sendable { var item: UninstallerItem; var ancestors: [String: Identity] }
    private struct Context: Sendable { var sequence: Int; var snapshot: UninstallerSnapshot; var appIdentity: [String: Identity]; var candidates: [Candidate] }
    private let home: URL
    private let selfApplicationURL: URL
    private let selfBundleIdentifier: String?
    private let runningApplicationURLs: @Sendable () async -> [URL]
    private let trash: @Sendable (URL) throws -> Void
    private var contexts: [UUID: Context] = [:]
    private var order: [UUID] = []
    private var activeID: UUID?
    private var sequence = 0
    private var activeSequence = -1
    private var removing = false
    init(home: URL, selfApplicationURL: URL, selfBundleIdentifier: String? = nil, runningApplicationURLs: @escaping @Sendable () async -> [URL] = { [] }, trash: @escaping @Sendable (URL) throws -> Void) {
        self.home = home.standardizedFileURL; self.selfApplicationURL = selfApplicationURL.standardizedFileURL; self.selfBundleIdentifier = selfBundleIdentifier
        self.runningApplicationURLs = runningApplicationURLs; self.trash = trash
    }
    func activateSnapshot(_ id: UUID) {
        guard let context = contexts[id], context.sequence >= activeSequence else { return }
        activeID = id; activeSequence = context.sequence
    }
    func scan(_ source: URL) async throws -> UninstallerSnapshot {
        guard !removing else { throw UninstallerFailure(key: "App Uninstaller Busy") }
        sequence += 1
        let scanSequence = sequence
        let app = source.standardizedFileURL
        let running = await runningApplicationURLs()
        guard !removing else { throw UninstallerFailure(key: "App Uninstaller Busy") }
        let metadata: (id: String, name: String)
        do { metadata = try validate(app, running: running) }
        catch { throw (error as? UninstallerFailure) ?? UninstallerFailure(key: "App Uninstaller Invalid App") }
        var appIdentity = try identities(app)
        appIdentity.merge(try identities(app.appendingPathComponent("Contents/Info.plist"))) { first, _ in first }
        var snapshot = UninstallerSnapshot(applicationURL: app, bundleIdentifier: metadata.id, displayName: metadata.name)
        var candidates: [Candidate] = []
        let library = home.appendingPathComponent("Library")
        var paths: [(URL, UninstallerItem.Kind)] = [(app, .application)]
        for (path, kind) in [("Preferences/\(metadata.id).plist", UninstallerItem.Kind.preferences), ("Caches/\(metadata.id)", .cache), ("Application Support/\(metadata.id)", .applicationSupport), ("Saved Application State/\(metadata.id).savedState", .savedState), ("Logs/\(metadata.id)", .logs), ("Containers/\(metadata.id)", .container)] { paths.append((library.appendingPathComponent(path), kind)) }
        let byHost = library.appendingPathComponent("Preferences/ByHost")
        do {
            _ = try identities(byHost)
            for url in try FileManager.default.contentsOfDirectory(at: byHost, includingPropertiesForKeys: nil) {
                try Task.checkCancellation()
                let name = url.lastPathComponent, prefix = metadata.id + ".", suffix = ".plist"
                if name.hasPrefix(prefix), name.hasSuffix(suffix), UUID(uuidString: String(name.dropFirst(prefix.count).dropLast(suffix.count))) != nil { paths.append((url, .preferences)) }
            }
        } catch is CancellationError { throw CancellationError() }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { }
        catch { snapshot.failures.append(.init(key: "App Uninstaller Scan Partial")) }
        for (url, kind) in paths {
            try Task.checkCancellation()
            do { _ = try FileManager.default.attributesOfItem(atPath: url.path) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { continue }
            catch { snapshot.failures.append(.init(key: "App Uninstaller Scan Partial", itemID: url.path)); continue }
            do {
                let ancestors = try identities(url)
                var bytes: Int64?
                do { bytes = try measure(url) } catch is CancellationError { throw CancellationError() } catch { snapshot.failures.append(.init(key: "App Uninstaller Scan Partial", itemID: url.path)) }
                let item = UninstallerItem(id: url.path, url: url, kind: kind, bytes: bytes)
                snapshot.items.append(item); candidates.append(.init(item: item, ancestors: ancestors))
            } catch is CancellationError { throw CancellationError() } catch { snapshot.failures.append(.init(key: "App Uninstaller Unsafe Path", itemID: url.path)) }
        }
        try Task.checkCancellation()
        contexts[snapshot.id] = Context(sequence: scanSequence, snapshot: snapshot, appIdentity: appIdentity, candidates: candidates); order.append(snapshot.id)
        while order.count > 6 {
            guard let index = order.firstIndex(where: { $0 != activeID && $0 != snapshot.id }) else { break }
            contexts.removeValue(forKey: order.remove(at: index))
        }
        return snapshot
    }
    func remove(_ request: UninstallerRemovalRequest) async throws -> UninstallerRemovalResult {
        let ids = Array(NSOrderedSet(array: request.itemIDs)) as? [String] ?? []
        guard !removing, activeID == request.snapshotID, let context = contexts[request.snapshotID] else { return .init(failures: ids.map { .init(key: "App Uninstaller Stale Scan", itemID: $0) }) }
        removing = true
        defer { removing = false }
        var result = UninstallerRemovalResult()
        let requested = Set(ids)
        let known = Set(context.candidates.map { $0.item.id })
        result.failures += ids.filter { !known.contains($0) }.map { .init(key: "App Uninstaller Stale Scan", itemID: $0) }
        let candidates = context.candidates.filter { requested.contains($0.item.id) }.sorted { $0.item.kind != .application && $1.item.kind == .application }
        for candidate in candidates {
            do {
                // Preserve the bundle when selected related files could not be removed. The
                // retained app identity is needed to safely authorize a later retry.
                guard candidate.item.kind != .application || result.failures.isEmpty else {
                    throw UninstallerFailure(key: "App Uninstaller Remove Failed")
                }
                try Task.checkCancellation()
                let running = await runningApplicationURLs()
                try Task.checkCancellation()
                let metadata = try validate(context.snapshot.applicationURL, running: running)
                guard metadata.id == context.snapshot.bundleIdentifier, try appIdentities(context.snapshot.applicationURL) == context.appIdentity,
                      try identities(candidate.item.url) == candidate.ancestors else { throw UninstallerFailure(key: "App Uninstaller Stale Scan") }
                try trash(candidate.item.url)
                result.removedItemIDs.append(candidate.item.id)
            } catch { result.failures.append(.wrapping(error, itemID: candidate.item.id)) }
        }
        // Successful items cannot be replayed through the same authorization.
        if var retained = contexts[request.snapshotID] { retained.candidates.removeAll { result.removedItemIDs.contains($0.item.id) }; contexts[request.snapshotID] = retained }
        return result
    }
    private func appIdentities(_ app: URL) throws -> [String: Identity] {
        var result = try identities(app)
        result.merge(try identities(app.appendingPathComponent("Contents/Info.plist"))) { first, _ in first }
        return result
    }
    private func validate(_ app: URL, running: [URL]) throws -> (id: String, name: String) {
        guard app.isFileURL, app.pathExtension.lowercased() == "app", app.host == nil || app.host == "" || app.host == "localhost",
              !["/System", "/Library", "/usr", "/bin", "/sbin", "/Network", "/Volumes"].contains(where: { app.path == $0 || app.path.hasPrefix($0 + "/") }),
              app != selfApplicationURL, !running.contains(where: { isSameApplication($0, app) }) else { throw UninstallerFailure(key: "App Uninstaller App Unavailable") }
        var parent = app.deletingLastPathComponent()
        while parent.path != "/" {
            guard parent.pathExtension.lowercased() != "app" else { throw UninstallerFailure(key: "App Uninstaller Invalid App") }
            parent.deleteLastPathComponent()
        }
        _ = try identities(app)
        let values = try app.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw UninstallerFailure(key: "App Uninstaller Invalid App") }
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        _ = try identities(infoURL)
        guard let dict = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any], let id = dict["CFBundleIdentifier"] as? String,
              !id.isEmpty, id.contains("."), !id.contains(".."), id.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.").inverted) == nil,
              !id.lowercased().hasPrefix("com.apple."), id != selfBundleIdentifier, dict["CFBundlePackageType"] as? String == "APPL" else { throw UninstallerFailure(key: "App Uninstaller Invalid App") }
        return (id, (dict["CFBundleDisplayName"] as? String) ?? (dict["CFBundleName"] as? String) ?? app.deletingPathExtension().lastPathComponent)
    }
    private func isSameApplication(_ runningURL: URL, _ candidateURL: URL) -> Bool {
        if runningURL.standardizedFileURL == candidateURL { return true }
        // Case-insensitive volumes and alternate volume paths can name the same
        // running bundle differently. Match its filesystem identity as well.
        guard let running = try? FileManager.default.attributesOfItem(atPath: runningURL.resolvingSymlinksInPath().path),
              let candidate = try? FileManager.default.attributesOfItem(atPath: candidateURL.path),
              let runningDevice = running[.systemNumber] as? NSNumber,
              let runningInode = running[.systemFileNumber] as? NSNumber,
              let candidateDevice = candidate[.systemNumber] as? NSNumber,
              let candidateInode = candidate[.systemFileNumber] as? NSNumber else { return false }
        return runningDevice == candidateDevice && runningInode == candidateInode
    }
    private func identities(_ url: URL) throws -> [String: Identity] {
        var result: [String: Identity] = [:], cursor = url.standardizedFileURL
        while cursor.path != "/" {
            let attributes = try FileManager.default.attributesOfItem(atPath: cursor.path)
            if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                // macOS presents these root-owned system aliases through standardized URLs.
                // Pin their own inode below; user-controlled links remain forbidden.
                let aliases = ["/var": "private/var", "/tmp": "private/tmp", "/etc": "private/etc"]
                guard let expected = aliases[cursor.path],
                      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0,
                      try FileManager.default.destinationOfSymbolicLink(atPath: cursor.path) == expected else { throw UninstallerFailure(key: "App Uninstaller Unsafe Path") }
            }
            guard let inode = attributes[.systemFileNumber] as? NSNumber, let device = attributes[.systemNumber] as? NSNumber else { throw UninstallerFailure(key: "App Uninstaller Unsafe Path") }
            result[cursor.path] = Identity(device: device.uint64Value, inode: inode.uint64Value)
            cursor.deleteLastPathComponent()
        }
        return result
    }
    private func measure(_ url: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let root = try url.resourceValues(forKeys: keys)
        if root.isDirectory != true {
            guard let size = root.totalFileAllocatedSize ?? root.fileAllocatedSize else { throw UninstallerFailure(key: "App Uninstaller Scan Partial") }
            return Int64(size)
        }
        var total: Int64 = 0
        var failed = false
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), errorHandler: { _, _ in failed = true; return false }) else { throw UninstallerFailure(key: "App Uninstaller Scan Partial") }
        for case let child as URL in enumerator {
            try Task.checkCancellation()
            let values = try child.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isDirectory != true {
                guard let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize else { throw UninstallerFailure(key: "App Uninstaller Scan Partial") }
                total += Int64(size)
            }
        }
        guard !failed else { throw UninstallerFailure(key: "App Uninstaller Scan Partial") }
        return total
    }
}
#endif
