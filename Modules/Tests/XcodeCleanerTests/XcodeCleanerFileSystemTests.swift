#if os(macOS)
import Foundation
import Testing
@testable import XcodeCleaner

struct XcodeCleanerFileSystemTests {
    @Test func displayedAuthorizationSurvivesLaterInventory() async throws {
        let fixture = try CleanerFixture(); defer { fixture.remove() }
        let file = try fixture.write("Library/Developer/Xcode/DerivedData/App/product")
        let adapter = XcodeCleanerFileSystem(home: fixture.home)
        let displayed = try await adapter.scan()
        await adapter.activateSnapshot(displayed.id)
        let item = try fixture.item(.derivedData, in: displayed)
        for _ in 0..<8 { _ = try await adapter.scan() }
        let result = try await adapter.clean(fixture.request(item, in: displayed))
        #expect(result.removedItemIDs == [item.id])
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func oneReplacedRootFailureIsScopedAndDoesNotPreventSecondCategoryCleanup() async throws {
        let fixture = try CleanerFixture(); defer { fixture.remove() }
        _ = try fixture.write("Library/Developer/Xcode/DerivedData/App/old")
        let package = try fixture.write("Library/Caches/org.swift.swiftpm/package")
        let adapter = XcodeCleanerFileSystem(home: fixture.home)
        let snapshot = try await adapter.scan()
        let build = try fixture.item(.derivedData, in: snapshot)
        let spm = try fixture.item(.spmCaches, in: snapshot)
        try FileManager.default.moveItem(at: fixture.url("Library/Developer/Xcode/DerivedData"), to: fixture.url("Previous"))
        let newFile = try fixture.write("Library/Developer/Xcode/DerivedData/App/new")
        let result = try await adapter.clean(.init(snapshotID: snapshot.id, itemIDs: [build.id, spm.id]))
        #expect(result.failures.contains { $0.itemID == build.id })
        #expect(result.removedItemIDs == [spm.id])
        #expect(FileManager.default.fileExists(atPath: newFile.path))
        #expect(!FileManager.default.fileExists(atPath: package.path))
    }
    @Test func derivedDataIncludesNestedBuildAndPackageArtifactsOnce() async throws {
        let fixture = try CleanerFixture(); defer { fixture.remove() }
        let paths = ["Build/product", "Index.noindex/index", "SourcePackages/checkouts/package", "ModuleCache.noindex/module"]
        var expected: Int64 = 0
        for path in paths {
            let file = try fixture.write("Library/Developer/Xcode/DerivedData/Example/\(path)")
            let values = try file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
            expected += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        let snapshot = try await XcodeCleanerFileSystem(home: fixture.home).scan()
        let items = snapshot.items.filter { $0.category == .derivedData }
        #expect(items.count == 1)
        #expect(items.first?.bytes == expected)
        #expect(snapshot.knownBytes == expected)
    }

    @Test func absentRootsDoNotBecomeFailures() async throws {
        let fixture = try CleanerFixture(); defer { fixture.remove() }
        let snapshot = try await XcodeCleanerFileSystem(home: fixture.home).scan()
        #expect(snapshot.failures.isEmpty)
        #expect(snapshot.knownBytes == 0)
    }

    @Test func cleaningOneCategoryPreservesOtherCachesAndArchives() async throws {
        let fixture = try CleanerFixture(); defer { fixture.remove() }
        let build = try fixture.write("Library/Developer/Xcode/DerivedData/App/Build/product")
        let spm = try fixture.write("Library/Caches/org.swift.swiftpm/package")
        let archive = try fixture.write("Library/Developer/Xcode/Archives/Keep.xcarchive/data")
        let source = try fixture.write("Projects/App/App.swift")
        let sdk = try fixture.write("Applications/Xcode.app/Contents/Developer/Platforms/SDK/data")
        let adapter = XcodeCleanerFileSystem(home: fixture.home)
        let snapshot = try await adapter.scan()
        let item = try fixture.item(.derivedData, in: snapshot)
        let result = try await adapter.clean(fixture.request(item, in: snapshot))
        #expect(result.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: build.path))
        #expect(FileManager.default.fileExists(atPath: fixture.url("Library/Developer/Xcode/DerivedData").path))
        for file in [spm, archive, source, sdk] { #expect(FileManager.default.fileExists(atPath: file.path)) }
    }

    @Test func symbolicLinkChildNeverDeletesOutsideSentinel() async throws {
        let fixture = try CleanerFixture(); defer { fixture.remove() }
        let sentinel = try fixture.write("Outside/precious")
        _ = try fixture.write("Library/Developer/Xcode/DerivedData/App/product")
        try FileManager.default.createSymbolicLink(at: fixture.url("Library/Developer/Xcode/DerivedData/external"), withDestinationURL: sentinel.deletingLastPathComponent())
        let adapter = XcodeCleanerFileSystem(home: fixture.home)
        let snapshot = try await adapter.scan()
        let item = try fixture.item(.derivedData, in: snapshot)
        _ = try await adapter.clean(fixture.request(item, in: snapshot))
        #expect(try Data(contentsOf: sentinel) == Data(repeating: 42, count: 16))
    }

    @Test func symbolicLinkAncestorIsReportedInsteadOfTraversed() async throws {
        let fixture = try CleanerFixture(); defer { fixture.remove() }
        let sentinel = try fixture.write("Outside/Xcode/DerivedData/product")
        try FileManager.default.createDirectory(at: fixture.url("Library"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.url("Library/Developer"), withDestinationURL: fixture.url("Outside"))
        let snapshot = try await XcodeCleanerFileSystem(home: fixture.home).scan()
        #expect(!snapshot.failures.isEmpty)
        #expect(snapshot.items.filter { $0.category == .derivedData }.allSatisfy { !$0.canClean })
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
    }

    @Test func replacementAfterScanCannotBeCleanedWithOldAuthorization() async throws {
        let fixture = try CleanerFixture(); defer { fixture.remove() }
        _ = try fixture.write("Library/Developer/Xcode/DerivedData/App/old")
        let adapter = XcodeCleanerFileSystem(home: fixture.home)
        let snapshot = try await adapter.scan()
        let item = try fixture.item(.derivedData, in: snapshot)
        try FileManager.default.moveItem(at: fixture.url("Library/Developer/Xcode/DerivedData"), to: fixture.url("PreviousDerivedData"))
        let fresh = try fixture.write("Library/Developer/Xcode/DerivedData/App/new")
        let result = try await adapter.clean(fixture.request(item, in: snapshot))
        #expect(!result.failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }

    @Test func unknownItemAndSnapshotCannotAuthorizeDeletion() async throws {
        let fixture = try CleanerFixture(); defer { fixture.remove() }
        let sentinel = try fixture.write("Library/Developer/Xcode/DerivedData/App/product")
        let adapter = XcodeCleanerFileSystem(home: fixture.home)
        _ = try await adapter.scan()
        let result = try await adapter.clean(CleanerCleanupRequest(snapshotID: UUID(), itemIDs: [sentinel.path]))
        #expect(!result.failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
    }
}
#endif
