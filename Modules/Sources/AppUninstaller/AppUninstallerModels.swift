#if os(macOS)
import Foundation

public struct UninstallerItem: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case application, preferences, cache, applicationSupport, savedState, logs, container }
    public var id: String
    public var url: URL
    public var kind: Kind
    public var bytes: Int64?
    public init(id: String, url: URL, kind: Kind, bytes: Int64? = nil) { self.id = id; self.url = url; self.kind = kind; self.bytes = bytes }
}
public struct UninstallerFailure: Error, Equatable, Sendable {
    public var key: String
    public var itemID: String?
    public init(key: String, itemID: String? = nil) { self.key = key; self.itemID = itemID }
    static func wrapping(_ error: Error, itemID: String? = nil) -> Self { (error as? Self).map { Self(key: $0.key, itemID: itemID ?? $0.itemID) } ?? Self(key: "App Uninstaller Remove Failed", itemID: itemID) }
}
public struct UninstallerSnapshot: Equatable, Sendable {
    public var id: UUID
    public var applicationURL: URL
    public var bundleIdentifier: String
    public var displayName: String
    public var items: [UninstallerItem]
    public var failures: [UninstallerFailure]
    public init(id: UUID = UUID(), applicationURL: URL, bundleIdentifier: String, displayName: String, items: [UninstallerItem] = [], failures: [UninstallerFailure] = []) { self.id = id; self.applicationURL = applicationURL; self.bundleIdentifier = bundleIdentifier; self.displayName = displayName; self.items = items; self.failures = failures }
}
public struct UninstallerRemovalRequest: Equatable, Sendable {
    public var snapshotID: UUID
    public var itemIDs: [String]
    public init(snapshotID: UUID, itemIDs: [String]) { self.snapshotID = snapshotID; self.itemIDs = itemIDs }
}
public struct UninstallerRemovalResult: Equatable, Sendable {
    public var removedItemIDs: [String]
    public var failures: [UninstallerFailure]
    public init(removedItemIDs: [String] = [], failures: [UninstallerFailure] = []) { self.removedItemIDs = removedItemIDs; self.failures = failures }
}
public struct UninstallerConfirmation: Equatable, Sendable {
    public var token: UUID
    public var hostID: UUID
    public var snapshotID: UUID
    public var itemIDs: [String]
}
#endif
