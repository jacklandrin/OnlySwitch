#if os(macOS)
import Foundation
import Darwin

/// Only explicit, session-authorized roots are mutable. The root itself is always retained.
public actor XcodeCleanerFileSystem {
    private let home: URL
    private struct Context: Sendable { var roots: [String: URL]; var identities: [String: String] }
    private var contexts = CleanerSnapshotContexts<Context>()
    private var sequence = 0
    public init(home: URL) { self.home = home.standardizedFileURL }
    private static var locations: [(CleanerCategory, String, String)] {
        [(.derivedData, "Xcode Cleaner Derived Data", "Library/Developer/Xcode/DerivedData"),
         (.xcodeCaches, "Xcode Cleaner Xcode Caches", "Library/Caches/com.apple.dt.Xcode"),
         (.spmCaches, "Xcode Cleaner SPM Caches", "Library/Caches/org.swift.swiftpm"),
         (.spmDownloads, "Xcode Cleaner SPM Downloads", ".swiftpm/cache"),
         (.simulatorCaches, "Xcode Cleaner Simulator Caches", "Library/Developer/CoreSimulator/Caches"),
         (.simulatorLogs, "Xcode Cleaner Simulator Logs", "Library/Logs/CoreSimulator")] +
        ["iOS", "watchOS", "tvOS", "visionOS"].map { (.deviceSupport, "Xcode Cleaner Device Support", "Library/Developer/Xcode/\($0) DeviceSupport") }
    }
    public func scan() async throws -> CleanerSnapshot {
        sequence += 1
        let ticket = sequence
        let (snapshot, context) = try await Self.inventory(home: home)
        try Task.checkCancellation()
        contexts.insert(context, id: snapshot.id, sequence: ticket)
        return snapshot
    }
    public func activateSnapshot(_ id: UUID) { _ = contexts.activate(id) }
    @concurrent private static func inventory(home: URL) async throws -> (CleanerSnapshot, Context) {
        try Task.checkCancellation()
        var snapshot = CleanerSnapshot()
        var newRoots: [String: URL] = [:], newIdentities: [String: String] = [:]
        for (category, title, path) in locations {
            try Task.checkCancellation()
            let url = home.appendingPathComponent(path), id = path
            do {
                try validateAncestors(url, home: home)
                guard try attributesIfPresent(url) != nil else { continue }
                let identity = try directoryIdentity(url)
                let bytes = try Self.measure(url)
                try validateAncestors(url, home: home)
                guard try directoryIdentity(url) == identity else { throw CleanerFailure(key: "Xcode Cleaner Stale Scan") }
                newRoots[id] = url; newIdentities[id] = identity
                snapshot.items.append(CleanerItem(id: id, category: category, title: title, bytes: bytes, requiresConfirmation: category == .deviceSupport, detail: url.path))
            } catch is CancellationError { throw CancellationError() }
            catch {
                snapshot.failures.append(CleanerFailure(key: "Xcode Cleaner Read Failed", detail: url.path + ": " + error.localizedDescription))
                snapshot.items.append(CleanerItem(id: id, category: category, title: title, bytes: nil, canClean: false, detail: url.path))
            }
        }
        return (snapshot, Context(roots: newRoots, identities: newIdentities))
    }
    public func clean(_ request: CleanerCleanupRequest) async throws -> CleanerCleanupResult {
        try Task.checkCancellation()
        guard let context = contexts[request.snapshotID] else { return .init(failures: request.itemIDs.map { .init(key: "Xcode Cleaner Stale Scan", itemID: $0) }) }
        contexts.pin(request.snapshotID)
        defer { contexts.unpin(request.snapshotID) }
        let roots = context.roots, identities = context.identities
        var result = CleanerCleanupResult()
        var seen = Set<String>()
        let orderedIDs = request.itemIDs.filter { seen.insert($0).inserted }
        for (offset, id) in orderedIDs.enumerated() {
            if Task.isCancelled {
                result.failures += orderedIDs[offset...].map { .init(key: "Xcode Cleaner Remove Failed", itemID: $0) }
                return result
            }
            guard let root = roots[id], let identity = identities[id] else { result.failures.append(.init(key: "Xcode Cleaner Stale Scan", itemID: id)); continue }
            do {
                try Self.validateAncestors(root, home: home)
                guard try Self.directoryIdentity(root) == identity else { throw CleanerFailure(key: "Xcode Cleaner Stale Scan") }
                let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard descriptor >= 0 else { throw POSIXError(.EACCES) }
                defer { close(descriptor) }
                var openedRoot = stat()
                let rootAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
                guard fstat(descriptor, &openedRoot) == 0,
                      (rootAttributes[.systemNumber] as? NSNumber)?.uint64Value == UInt64(openedRoot.st_dev),
                      (rootAttributes[.systemFileNumber] as? NSNumber)?.uint64Value == UInt64(openedRoot.st_ino),
                      try Self.directoryIdentity(root) == identity else { throw CleanerFailure(key: "Xcode Cleaner Stale Scan") }
                let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                var failed = false
                for child in children {
                    try Task.checkCancellation()
                    do {
                        try Self.validateAncestors(root, home: home)
                        guard try Self.directoryIdentity(root) == identity, child.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path else { throw CleanerFailure(key: "Xcode Cleaner Stale Scan") }
                        // Descriptor-relative traversal prevents a replaced descendant from redirecting deletion.
                        try Self.removeEntry(parent: descriptor, name: child.lastPathComponent)
                    } catch is CancellationError {
                        result.failures += orderedIDs[offset...].map { .init(key: "Xcode Cleaner Remove Failed", itemID: $0, mayHaveRemovedContents: $0 == id) }
                        return result
                    }
                    catch { failed = true; result.failures.append(.init(key: "Xcode Cleaner Remove Failed", detail: child.lastPathComponent + ": " + error.localizedDescription, itemID: id, mayHaveRemovedContents: true)) }
                }
                if !failed { result.cleanedIDs.append(id) }
            } catch is CancellationError {
                result.failures += orderedIDs[offset...].map { .init(key: "Xcode Cleaner Remove Failed", itemID: $0, mayHaveRemovedContents: $0 == id) }
                return result
            }
            catch { result.failures.append(CleanerFailure.wrapping(error).scoped(to: id)) }
        }
        return result
    }
    private static func validateAncestors(_ url: URL, home: URL) throws {
        var current = url
        while current.path != "/" {
            if let attributes = try attributesIfPresent(current), attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw CleanerFailure(key: "Xcode Cleaner Unsafe Location", detail: current.path) }
            if current == home { return }
            current.deleteLastPathComponent()
        }
        throw CleanerFailure(key: "Xcode Cleaner Unsafe Location")
    }
    private static func removeEntry(parent: Int32, name: String) throws {
        try Task.checkCancellation()
        var original = stat()
        guard fstatat(parent, name, &original, AT_SYMLINK_NOFOLLOW) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if original.st_mode & S_IFMT == S_IFDIR {
            let child = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard child >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            defer { close(child) }
            var opened = stat()
            guard fstat(child, &opened) == 0, original.st_ino == opened.st_ino, original.st_dev == opened.st_dev else { throw CleanerFailure(key: "Xcode Cleaner Stale Scan") }
            let iterationFD = dup(child)
            guard iterationFD >= 0 else { throw POSIXError(.EIO) }
            guard let directory = fdopendir(iterationFD) else { close(iterationFD); throw POSIXError(.EIO) }
            defer { closedir(directory) }
            while let entry = readdir(directory) {
                let childName = withUnsafePointer(to: entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if childName == "." || childName == ".." { continue }
                try removeEntry(parent: child, name: childName)
            }
            var current = stat()
            guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0, current.st_ino == opened.st_ino, current.st_dev == opened.st_dev else { throw CleanerFailure(key: "Xcode Cleaner Stale Scan") }
            guard unlinkat(parent, name, AT_REMOVEDIR) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } else {
            guard unlinkat(parent, name, 0) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
    }
    private static func attributesIfPresent(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
    }
    private static func directoryIdentity(_ url: URL) throws -> String {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard a[.type] as? FileAttributeType == .typeDirectory else { throw CleanerFailure(key: "Xcode Cleaner Unsafe Location") }
        return "\(a[.systemNumber] ?? ""):\(a[.systemFileNumber] ?? ""):\(a[.creationDate] ?? "")"
    }
    static func measure(_ root: URL) throws -> Int64 {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        var enumerationError: (any Error)?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw CleanerFailure(key: "Xcode Cleaner Read Failed") }
        var size: Int64 = 0, seen = Set<String>()
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true else { continue }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let identity = "\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? "")"
            if seen.insert(identity).inserted { size += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0) }
        }
        if let enumerationError { throw enumerationError }
        return size
    }
}
#endif
