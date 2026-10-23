#if os(macOS)
import Foundation

public enum CleanerCategory: String, Sendable, CaseIterable {
    case derivedData, xcodeCaches, spmCaches, spmDownloads, simulatorCaches, simulatorLogs, deviceSupport, simulatorDevice, simulatorRuntime
}
public struct CleanerItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var category: CleanerCategory
    public var title: String
    public var bytes: Int64?
    public var canClean: Bool
    public var requiresConfirmation: Bool
    public var detail: String
    public var statusKey: String?
    public var runtimeIdentifier: String?
    public var runtimeName: String?
    public init(id: String, category: CleanerCategory, title: String, bytes: Int64?, canClean: Bool = true, requiresConfirmation: Bool = false, detail: String = "", statusKey: String? = nil, runtimeIdentifier: String? = nil, runtimeName: String? = nil) {
        self.id = id; self.category = category; self.title = title; self.bytes = bytes; self.canClean = canClean; self.requiresConfirmation = requiresConfirmation; self.detail = detail; self.statusKey = statusKey; self.runtimeIdentifier = runtimeIdentifier; self.runtimeName = runtimeName
    }
}
public struct CleanerSnapshot: Equatable, Sendable {
    public var id: UUID
    public var items: [CleanerItem]
    public var failures: [CleanerFailure]
    public init(id: UUID = UUID(), items: [CleanerItem] = [], failures: [CleanerFailure] = []) { self.id = id; self.items = items; self.failures = failures }
    public var knownBytes: Int64 { items.compactMap(\.bytes).reduce(0, +) }
    public var hasUnknownBytes: Bool { items.contains { $0.bytes == nil } || !failures.isEmpty }
}
public struct CleanerFailure: Error, Equatable, Sendable {
    public var key: String
    public var detail: String?
    public var itemID: String?
    public var mayHaveRemovedContents: Bool
    public init(key: String, detail: String? = nil, itemID: String? = nil, mayHaveRemovedContents: Bool = false) {
        self.key = key; self.detail = detail; self.itemID = itemID; self.mayHaveRemovedContents = mayHaveRemovedContents
    }
    func scoped(to id: String, partial: Bool = false) -> Self {
        var copy = self; copy.itemID = id; copy.mayHaveRemovedContents = copy.mayHaveRemovedContents || partial
        return copy
    }
    static func wrapping(_ error: any Error) -> Self { (error as? Self) ?? Self(key: "Xcode Cleaner Operation Failed", detail: error.localizedDescription) }
}
public struct CleanerCleanupRequest: Equatable, Sendable {
    public var snapshotID: UUID
    public var itemIDs: [String]
    public init(snapshotID: UUID, itemIDs: [String]) { self.snapshotID = snapshotID; self.itemIDs = itemIDs }
}
public struct CleanerCleanupResult: Equatable, Sendable {
    public var removedItemIDs: [String]
    public var confirmedBytes: Int64?
    public var cleanedIDs: [String] { get { removedItemIDs } set { removedItemIDs = newValue } }
    public var failures: [CleanerFailure]
    public init(removedItemIDs: [String] = [], confirmedBytes: Int64? = nil, failures: [CleanerFailure] = []) { self.removedItemIDs = removedItemIDs; self.confirmedBytes = confirmedBytes; self.failures = failures }
}
public struct CleanerBatchConfirmation: Equatable, Sendable {
    public var token: UUID
    public var hostID: UUID
    public var snapshotID: UUID
    public var itemIDs: [String]
    public init(token: UUID, hostID: UUID, snapshotID: UUID, itemIDs: [String]) {
        self.token = token; self.hostID = hostID; self.snapshotID = snapshotID; self.itemIDs = itemIDs
    }
}
#endif
