#if os(macOS)
import Foundation
import Testing
@testable import AppUninstaller

struct AppUninstallerFileSystemTests {
    @Test func unreadableCacheReportsPartialScanAndUnknownSize() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        try fixture.write("Library/Caches/org.example.Editor/payload")
        let cache = fixture.url("Library/Caches/org.example.Editor")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: cache.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cache.path) }
        let snapshot = try await fixture.makeFileSystem().scan(fixture.applicationURL)
        let item = try #require(snapshot.items.first { $0.kind == .cache })
        #expect(item.bytes == nil)
        #expect(snapshot.failures.contains { $0.itemID == item.id })
    }

    @Test func inventoryMatchesOnlyClosedAllowlistAndValidByHostUUID() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let exact = ["Preferences/org.example.Editor.plist", "Caches/org.example.Editor/payload", "Application Support/org.example.Editor/payload", "Saved Application State/org.example.Editor.savedState/payload", "Logs/org.example.Editor/payload", "Containers/org.example.Editor/payload", "Preferences/ByHost/org.example.Editor.AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist"]
        for path in exact { try fixture.write("Library/" + path) }
        for path in ["Preferences/org.example.EditorHelper.plist", "Preferences/ByHost/org.example.Editor.not-a-uuid.plist", "Group Containers/org.example.Editor/payload", "Application Support/Example/payload", "LaunchAgents/org.example.Editor.plist"] { try fixture.write("Library/" + path) }
        let snapshot = try await fixture.makeFileSystem().scan(fixture.applicationURL)
        #expect(snapshot.bundleIdentifier == "org.example.Editor")
        #expect(snapshot.items.count == 8)
        #expect(Set(snapshot.items.map(\.url)).count == snapshot.items.count)
        #expect(!snapshot.items.contains { $0.url.path.contains("EditorHelper") || $0.url.path.contains("Group Containers") || $0.url.path.contains("not-a-uuid") })
    }

    @Test(arguments: ["../escape", "org/example", "org\\example", "org..example", "", "org.example\nEditor", "com.apple.Editor"])
    func malformedOrProtectedBundleIDsAreRejected(identifier: String) async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        try fixture.makeApplication(identifier: identifier)
        do { _ = try await fixture.makeFileSystem().scan(fixture.applicationURL); Issue.record("Unsafe app metadata accepted") } catch is UninstallerFailure { }
    }

    @Test func invalidAppAndRemoteURLAreRejected() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let fake = fixture.url("Fake.app")
        try FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        for target in [fake, fixture.url("missing.app"), URL(string: "https://example.org/Example.app")!, URL(fileURLWithPath: "/System/Applications/Example.app")] {
            do { _ = try await fixture.makeFileSystem().scan(target); Issue.record("Invalid or protected app accepted") } catch is UninstallerFailure { }
        }
    }

    @Test func selfAndRunningAppsCannotBeScanned() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        do { _ = try await fixture.makeFileSystem(selfURL: fixture.applicationURL).scan(fixture.applicationURL); Issue.record("Self uninstall accepted") } catch is UninstallerFailure { }
        let running = UninstallerRunningApps(); await running.set([fixture.applicationURL])
        do { _ = try await fixture.makeFileSystem(running: running).scan(fixture.applicationURL); Issue.record("Running app accepted") } catch is UninstallerFailure { }
    }

    @Test func symlinkedAppAndSymlinkedLibraryAncestorAreNeverAuthorized() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let alias = fixture.url("Alias.app")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.applicationURL)
        do { _ = try await fixture.makeFileSystem().scan(alias); Issue.record("Symlink app accepted") } catch is UninstallerFailure { }
        try fixture.write("outside/org.example.Editor/payload")
        try FileManager.default.createDirectory(at: fixture.url("Library"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.url("Library/Caches"), withDestinationURL: fixture.url("outside"))
        let snapshot = try await fixture.makeFileSystem().scan(fixture.applicationURL)
        #expect(!snapshot.items.contains { $0.kind == .cache })
    }

    @Test func symlinkedCandidateIsExcludedAndNestedSymlinkDoesNotAddItsTarget() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let outside = try fixture.write("outside/payload")
        try FileManager.default.createDirectory(at: fixture.url("Library/Caches/org.example.Editor"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.url("Library/Caches/org.example.Editor/link"), withDestinationURL: outside)
        try FileManager.default.createDirectory(at: fixture.url("Library/Preferences"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.url("Library/Preferences/org.example.Editor.plist"), withDestinationURL: outside)
        let snapshot = try await fixture.makeFileSystem().scan(fixture.applicationURL)
        #expect(!snapshot.items.contains { $0.kind == .preferences || $0.url == outside })
    }

    @Test func missingLibraryRootsAreNormalAndNoTrashOccursDuringScan() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let sink = UninstallerTrashSink()
        let snapshot = try await fixture.makeFileSystem(sink: sink).scan(fixture.applicationURL)
        #expect(snapshot.items.count == 1)
        #expect(snapshot.failures.isEmpty)
        #expect(sink.urls.isEmpty)
    }

    @Test func unknownOrUnactivatedSnapshotCannotAuthorizeTrash() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let sink = UninstallerTrashSink(), scanner = fixture.makeFileSystem(sink: sink)
        let snapshot = try await scanner.scan(fixture.applicationURL)
        for id in [UUID(), snapshot.id] {
            do { let result = try await scanner.remove(.init(snapshotID: id, itemIDs: snapshot.items.map(\.id))); #expect(result.removedItemIDs.isEmpty) } catch is UninstallerFailure { }
        }
        #expect(sink.urls.isEmpty)
    }

    @Test func forgedPathIDCannotAuthorizeArbitraryFile() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let outside = try fixture.write("unrelated.txt")
        let sink = UninstallerTrashSink(), scanner = fixture.makeFileSystem(sink: sink)
        let snapshot = try await scanner.scan(fixture.applicationURL); await scanner.activateSnapshot(snapshot.id)
        do { let result = try await scanner.remove(.init(snapshotID: snapshot.id, itemIDs: [outside.path])); #expect(result.removedItemIDs.isEmpty) } catch is UninstallerFailure { }
        #expect(sink.urls.isEmpty)
    }

    @Test func replacedAppCannotBeTrashedUsingOldInventory() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let sink = UninstallerTrashSink(), scanner = fixture.makeFileSystem(sink: sink)
        let snapshot = try await scanner.scan(fixture.applicationURL); await scanner.activateSnapshot(snapshot.id)
        // Move the old inode aside so the filesystem cannot immediately reuse it.
        try FileManager.default.moveItem(at: fixture.applicationURL, to: fixture.url("old.app"))
        try fixture.makeApplication()
        let result = try await scanner.remove(.init(snapshotID: snapshot.id, itemIDs: snapshot.items.map(\.id)))
        #expect(result.removedItemIDs.isEmpty)
        #expect(!result.failures.isEmpty)
        #expect(sink.urls.isEmpty)
    }

    @Test(arguments: [false, true])
    func replacedRootOrNewSymlinkInvalidatesCandidate(useSymlink: Bool) async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        try fixture.write("Library/Caches/org.example.Editor/payload")
        let sink = UninstallerTrashSink(), scanner = fixture.makeFileSystem(sink: sink)
        let snapshot = try await scanner.scan(fixture.applicationURL); await scanner.activateSnapshot(snapshot.id)
        let cache = try #require(snapshot.items.first { $0.kind == .cache })
        try FileManager.default.moveItem(at: fixture.url("Library/Caches"), to: fixture.url("oldCaches"))
        if useSymlink { try FileManager.default.createSymbolicLink(at: fixture.url("Library/Caches"), withDestinationURL: fixture.url("oldCaches")) }
        else { try fixture.write("Library/Caches/org.example.Editor/new") }
        let result = try await scanner.remove(.init(snapshotID: snapshot.id, itemIDs: [cache.id]))
        #expect(result.removedItemIDs.isEmpty)
        #expect(!result.failures.isEmpty)
        #expect(sink.urls.isEmpty)
    }

    @Test func appStartingAfterScanBlocksRemoval() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let running = UninstallerRunningApps(), sink = UninstallerTrashSink()
        let scanner = fixture.makeFileSystem(sink: sink, running: running)
        let snapshot = try await scanner.scan(fixture.applicationURL); await scanner.activateSnapshot(snapshot.id)
        await running.set([fixture.applicationURL])
        let result = try await scanner.remove(.init(snapshotID: snapshot.id, itemIDs: snapshot.items.map(\.id)))
        #expect(result.removedItemIDs.isEmpty)
        #expect(!result.failures.isEmpty)
        #expect(sink.urls.isEmpty)
    }

    @Test func duplicateIDsAreTrashedOnceAndAssociatedFilesPrecedeApp() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let pref = try fixture.write("Library/Preferences/org.example.Editor.plist")
        let sink = UninstallerTrashSink(), scanner = fixture.makeFileSystem(sink: sink)
        let snapshot = try await scanner.scan(fixture.applicationURL); await scanner.activateSnapshot(snapshot.id)
        let ids = snapshot.items.map(\.id)
        let result = try await scanner.remove(.init(snapshotID: snapshot.id, itemIDs: ids + ids))
        #expect(Set(result.removedItemIDs) == Set(ids))
        #expect(sink.urls == [pref, fixture.applicationURL])
    }

    @Test func relatedTrashFailurePreservesApplicationForRetry() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        try fixture.write("Library/Preferences/org.example.Editor.plist")
        let sink = UninstallerTrashSink(failingName: "org.example.Editor.plist"), scanner = fixture.makeFileSystem(sink: sink)
        let snapshot = try await scanner.scan(fixture.applicationURL); await scanner.activateSnapshot(snapshot.id)
        let result = try await scanner.remove(.init(snapshotID: snapshot.id, itemIDs: snapshot.items.map(\.id)))
        #expect(result.removedItemIDs.isEmpty)
        #expect(result.failures.count == 2)
        #expect(sink.urls.isEmpty)
    }
    @Test func runningApplicationAliasBlocksScanAndRemovalByFilesystemIdentity() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let alias = fixture.url("RunningAlias.app")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.applicationURL)
        let running = UninstallerRunningApps(), sink = UninstallerTrashSink()
        let scanner = fixture.makeFileSystem(sink: sink, running: running)
        let snapshot = try await scanner.scan(fixture.applicationURL)
        await scanner.activateSnapshot(snapshot.id)
        await running.set([alias])
        await #expect(throws: UninstallerFailure.self) { try await scanner.scan(fixture.applicationURL) }
        let result = try await scanner.remove(.init(snapshotID: snapshot.id, itemIDs: snapshot.items.map(\.id)))
        #expect(result.removedItemIDs.isEmpty)
        #expect(result.failures.count == snapshot.items.count)
        #expect(sink.urls.isEmpty)
    }

    @Test func separateCopyWithOnlySwitchBundleIdentifierIsProtected() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let scanner = AppUninstallerFileSystem(home: fixture.home, selfApplicationURL: fixture.url("Different.app"), selfBundleIdentifier: "org.example.Editor", trash: { _ in Issue.record("Self app must never be trashed") })
        await #expect(throws: UninstallerFailure.self) { try await scanner.scan(fixture.applicationURL) }
    }

    @Test func changedBundleMetadataInvalidatesPriorAuthorization() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let sink = UninstallerTrashSink(), scanner = fixture.makeFileSystem(sink: sink)
        let snapshot = try await scanner.scan(fixture.applicationURL)
        await scanner.activateSnapshot(snapshot.id)
        try fixture.makeApplication(identifier: "org.example.OtherApp")
        let result = try await scanner.remove(.init(snapshotID: snapshot.id, itemIDs: snapshot.items.map(\.id)))
        #expect(result.removedItemIDs.isEmpty)
        #expect(result.failures.count == snapshot.items.count)
        #expect(sink.urls.isEmpty)
    }

    @Test func earlierSnapshotCannotReactivateAfterNewSnapshotWasDisplayed() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let sink = UninstallerTrashSink(), scanner = fixture.makeFileSystem(sink: sink)
        let earlier = try await scanner.scan(fixture.applicationURL)
        let latest = try await scanner.scan(fixture.applicationURL)
        await scanner.activateSnapshot(latest.id)
        await scanner.activateSnapshot(earlier.id)
        let result = try await scanner.remove(.init(snapshotID: earlier.id, itemIDs: earlier.items.map(\.id)))
        #expect(result.removedItemIDs.isEmpty)
        #expect(sink.urls.isEmpty)
        let accepted = try await scanner.remove(.init(snapshotID: latest.id, itemIDs: latest.items.map(\.id)))
        #expect(accepted.removedItemIDs == latest.items.map(\.id))
    }

    @Test func partialRemovalContinuesOtherDataAndRetryCanRemoveBundleLast() async throws {
        let fixture = try UninstallerFixture(); defer { fixture.remove() }
        let preferences = try fixture.write("Library/Preferences/org.example.Editor.plist")
        let cache = try fixture.write("Library/Caches/org.example.Editor/payload").deletingLastPathComponent()
        let sink = UninstallerRetryTrashSink(home: fixture.home, initiallyFailingURL: preferences)
        let scanner = AppUninstallerFileSystem(home: fixture.home, selfApplicationURL: fixture.url("OnlySwitch.app"), trash: { try sink.trash($0) })
        let snapshot = try await scanner.scan(fixture.applicationURL)
        await scanner.activateSnapshot(snapshot.id)
        let first = try await scanner.remove(.init(snapshotID: snapshot.id, itemIDs: snapshot.items.map(\.id)))
        #expect(first.removedItemIDs == [cache.path])
        #expect(Set(first.failures.compactMap(\.itemID)) == [preferences.path, fixture.applicationURL.path])
        #expect(FileManager.default.fileExists(atPath: fixture.applicationURL.path))
        sink.allowRetry()
        let remainingIDs = snapshot.items.map(\.id).filter { !first.removedItemIDs.contains($0) }
        let retry = try await scanner.remove(.init(snapshotID: snapshot.id, itemIDs: remainingIDs))
        #expect(retry.failures.isEmpty)
        #expect(retry.removedItemIDs == [preferences.path, fixture.applicationURL.path])
        #expect(FileManager.default.fileExists(atPath: fixture.applicationURL.path) == false)
        let replay = try await scanner.remove(.init(snapshotID: snapshot.id, itemIDs: snapshot.items.map(\.id)))
        #expect(replay.removedItemIDs.isEmpty)
        #expect(replay.failures.count == snapshot.items.count)
    }
}

/// Real fixture moves expose missing-path retry bugs without touching the user's Trash.
private final class UninstallerRetryTrashSink: @unchecked Sendable {
    private let lock = NSLock()
    private let home: URL
    private let initiallyFailingURL: URL
    private var permitsRetry = false
    init(home: URL, initiallyFailingURL: URL) { self.home = home; self.initiallyFailingURL = initiallyFailingURL }
    func allowRetry() { lock.lock(); defer { lock.unlock() }; permitsRetry = true }
    func trash(_ url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        if url == initiallyFailingURL, !permitsRetry { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.moveItem(at: url, to: home.appendingPathComponent("trashed-" + UUID().uuidString))
    }
}
#endif
