#if os(macOS)
import Foundation
import Testing
@testable import Screenshots

struct ScreenshotOrderingTests {
    @Test func displayOrderPutsPinnedFirstThenNewest() {
        let old = item(createdAt: 10), new = item(createdAt: 20), pinnedOld = item(createdAt: 5, pinned: true)
        #expect([old, pinnedOld, new].displayOrdered().map(\.id) == [pinnedOld.id, new.id, old.id])
    }

    @Test func displayOrderIsStableByIDForEqualDates() {
        let a = item(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, createdAt: 10)
        let b = item(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, createdAt: 10)
        #expect([b, a].displayOrdered().map(\.id) == [a.id, b.id])
        #expect([a, b].displayOrdered().map(\.id) == [a.id, b.id])
    }
}
struct ScreenshotLibraryFixture {
    let root: URL
    var folder: URL { root.appendingPathComponent("Library Folder", isDirectory: true) }
    var manifest: URL { root.appendingPathComponent("Support/Screenshots/library.json") }
    init() throws { root = try makeTemporaryDirectory(); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func library(trash: ScreenshotTrashRecorder = .init(), now: TimeInterval = 100) -> ScreenshotLibrary {
        ScreenshotLibrary(folder: folder, manifestURL: manifest, trash: { try trash.trash($0) }, now: { Date(timeIntervalSince1970: now) }, uuid: { UUID() })
    }
    @discardableResult func capture(_ name: String) throws -> URL { try writePNG(to: folder.appendingPathComponent(name)) }
    func writeManifest(_ items: [ScreenshotItem]) throws {
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: manifest)
    }
}

struct ScreenshotLibraryTests {
    @Test func loadDropsItemsWhoseFilesWereRemoved() async throws {
        let fixture = try ScreenshotLibraryFixture(); defer { fixture.remove() }
        let library = fixture.library()
        let kept = try #require(try await library.add(fileURL: try fixture.capture("Kept.png")))
        let gone = try #require(try await library.add(fileURL: try fixture.capture("Gone.png")))
        try FileManager.default.removeItem(at: fixture.folder.appendingPathComponent(gone.fileName))
        #expect(try await fixture.library().load().map(\.id) == [kept.id])
        let persisted = try JSONDecoder().decode([ScreenshotItem].self, from: Data(contentsOf: fixture.manifest))
        #expect(persisted.map(\.id) == [kept.id])
    }

    @Test func addIgnoresFilesOutsideFolderHiddenFilesAndNonImages() async throws {
        let fixture = try ScreenshotLibraryFixture(); defer { fixture.remove() }
        let library = fixture.library()
        let hidden = try fixture.capture(".Screenshot x.png")
        let text = fixture.folder.appendingPathComponent("a.txt"); try Data("text".utf8).write(to: text)
        let outside = try writePNG(to: fixture.root.appendingPathComponent("x.png"))
        let nested = try writePNG(to: fixture.folder.appendingPathComponent("Nested/y.png"))
        let traversal = fixture.folder.appendingPathComponent("Nested/../../x.png")
        let link = fixture.folder.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        for url in [hidden, text, outside, nested, traversal, link, URL(fileURLWithPath: "/tmp/x.png"), fixture.folder.appendingPathComponent("missing.png")] {
            #expect(try await library.add(fileURL: url) == nil, "accepted \(url.path)")
        }
        #expect(try await library.load().isEmpty)
    }

    @Test func addRecordsRelativeNameAndCreationDate() async throws {
        let fixture = try ScreenshotLibraryFixture(); defer { fixture.remove() }
        let added = try #require(try await fixture.library(now: 42).add(fileURL: try fixture.capture("Screenshot 1.png")))
        #expect(added.fileName == "Screenshot 1.png")
        #expect(added.createdAt == Date(timeIntervalSince1970: 42))
        #expect(!added.isPinned && added.revision == 0)
    }

    @Test func addIsIdempotentForSameFileName() async throws {
        let fixture = try ScreenshotLibraryFixture(); defer { fixture.remove() }
        let library = fixture.library()
        let url = try fixture.capture("Screenshot.png")
        let first = try await library.add(fileURL: url)
        let second = try await library.add(fileURL: url)
        #expect(first != nil && first == second)
        #expect(try await library.load().count == 1)
    }

    @Test func pinPersistsAcrossLibraryInstances() async throws {
        let fixture = try ScreenshotLibraryFixture(); defer { fixture.remove() }
        let library = fixture.library()
        let older = try #require(try await fixture.library(now: 1).add(fileURL: try fixture.capture("Old.png")))
        _ = try await library.load()
        _ = try #require(try await library.add(fileURL: try fixture.capture("New.png")))
        let pinned = try await library.setPinned(older.id, true)
        #expect(pinned.first?.id == older.id && pinned.first?.isPinned == true)
        let reloaded = try await fixture.library().load()
        #expect(reloaded.first { $0.id == older.id }?.isPinned == true)
        await #expect(throws: ScreenshotFailure.self) { try await library.setPinned(UUID(), true) }
    }

    @Test func trashOnlyTouchesRecordedFilesAndReportsFailures() async throws {
        let fixture = try ScreenshotLibraryFixture(); defer { fixture.remove() }
        let recorder = ScreenshotTrashRecorder(failingName: "Locked.png")
        let library = fixture.library(trash: recorder)
        let a = try #require(try await library.add(fileURL: try fixture.capture("A.png")))
        let locked = try #require(try await library.add(fileURL: try fixture.capture("Locked.png")))
        let untracked = try fixture.capture("Untracked.png")
        let result = await library.trash([a.id, locked.id])
        #expect(result.0.map(\.id) == [locked.id])
        #expect(result.1 == [ScreenshotFailure(key: "Screenshot Trash Failed", itemID: locked.id)])
        #expect(recorder.urls.map(\.lastPathComponent) == ["A.png"])
        #expect(FileManager.default.fileExists(atPath: untracked.path))
        // Reloading adopts the untracked image (load imports unrecorded folder files) but never trashes it.
        #expect(try await fixture.library().load().map(\.fileName).sorted() == ["Locked.png", "Untracked.png"])
    }

    @Test func trashUnknownIDIsAFailureNotAPathOperation() async throws {
        let fixture = try ScreenshotLibraryFixture(); defer { fixture.remove() }
        let recorder = ScreenshotTrashRecorder()
        let library = fixture.library(trash: recorder)
        try fixture.capture("Untracked.png")
        let unknown = UUID()
        let result = await library.trash([unknown])
        #expect(result.0.isEmpty)
        #expect(result.1 == [ScreenshotFailure(key: "Screenshot Trash Failed", itemID: unknown)])
        #expect(recorder.urls.isEmpty)
    }

    @Test func replaceImageWritesAtomicallyAndBumpsRevision() async throws {
        let fixture = try ScreenshotLibraryFixture(); defer { fixture.remove() }
        let library = fixture.library()
        let added = try #require(try await library.add(fileURL: try fixture.capture("Edit.png")))
        let edited = try pngData(width: 8, height: 2, color: (0, 0, 1))
        let items = try await library.replaceImage(added.id, data: edited)
        #expect(items.first { $0.id == added.id }?.revision == 1)
        #expect(try Data(contentsOf: fixture.folder.appendingPathComponent("Edit.png")) == edited)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path) == ["Edit.png"])
        #expect(try await fixture.library().load().first?.revision == 1)
        await #expect(throws: ScreenshotFailure.self) { try await library.replaceImage(UUID(), data: edited) }
    }

    @Test func loadImportsUnrecordedImagesInTheFolderAndIgnoresOthers() async throws {
        let fixture = try ScreenshotLibraryFixture(); defer { fixture.remove() }
        let recorded = try #require(try await fixture.library(now: 50).add(fileURL: try fixture.capture("Recorded.png")))
        let offline = try fixture.capture("Offline.png")
        let created = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.creationDate: created, .modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: offline.path)
        try fixture.capture(".onlyswitch-edit-\(UUID().uuidString).png")
        try fixture.capture(".Screenshot hidden.png")
        try Data("text".utf8).write(to: fixture.folder.appendingPathComponent("notes.txt"))
        try writePNG(to: fixture.folder.appendingPathComponent("Nested/inner.png"))
        let outside = try writePNG(to: fixture.root.appendingPathComponent("outside.png"))
        try FileManager.default.createSymbolicLink(at: fixture.folder.appendingPathComponent("link.png"), withDestinationURL: outside)
        let loaded = try await fixture.library().load()
        #expect(loaded.map(\.fileName) == ["Offline.png", "Recorded.png"])
        #expect(loaded.first { $0.fileName == "Recorded.png" }?.id == recorded.id)
        let imported = try #require(loaded.first { $0.fileName == "Offline.png" })
        #expect(imported.createdAt == created && !imported.isPinned && imported.revision == 0)
        let persisted = try JSONDecoder().decode([ScreenshotItem].self, from: Data(contentsOf: fixture.manifest))
        #expect(Set(persisted.map(\.fileName)) == ["Recorded.png", "Offline.png"])
        // Importing is idempotent: a second load keeps the same id.
        #expect(try await fixture.library().load().first { $0.fileName == "Offline.png" }?.id == imported.id)
    }

    @Test func corruptManifestStartsEmptyAndIsRewritten() async throws {
        let fixture = try ScreenshotLibraryFixture(); defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fixture.manifest)
        #expect(try await fixture.library().load().isEmpty)
        #expect(try JSONDecoder().decode([ScreenshotItem].self, from: Data(contentsOf: fixture.manifest)).isEmpty)
    }

    @Test func fileNameWithPathTraversalIsRejected() async throws {
        let fixture = try ScreenshotLibraryFixture(); defer { fixture.remove() }
        try writePNG(to: fixture.root.appendingPathComponent("x.png"))
        try fixture.capture("ok.png")
        let bad = [item(createdAt: 1, fileName: "../x.png"), item(createdAt: 2, fileName: ".."), item(createdAt: 3, fileName: "/etc/x.png"), item(createdAt: 4, fileName: "Nested/ok.png")]
        let good = item(createdAt: 5, fileName: "ok.png")
        try fixture.writeManifest(bad + [good])
        let library = fixture.library()
        #expect(try await library.load().map(\.id) == [good.id])
        for entry in bad { #expect(await library.fileURL(entry.id) == nil) }
        #expect(await library.fileURL(good.id) == fixture.folder.appendingPathComponent("ok.png"))
    }

    /// Copy, open, drag, fly-in and the editor all resolve through `fileURL`; a recorded file later swapped for a
    /// symbolic link (or removed) must not hand out a path that follows the link.
    @Test func fileURLRejectsRecordedFileReplacedBySymlinkOrRemoved() async throws {
        let fixture = try ScreenshotLibraryFixture(); defer { fixture.remove() }
        let library = fixture.library()
        let swapped = try #require(try await library.add(fileURL: try fixture.capture("Swapped.png")))
        let removed = try #require(try await library.add(fileURL: try fixture.capture("Removed.png")))
        let outside = try writePNG(to: fixture.root.appendingPathComponent("secret.png"))
        let swappedURL = fixture.folder.appendingPathComponent(swapped.fileName)
        try FileManager.default.removeItem(at: swappedURL)
        try FileManager.default.createSymbolicLink(at: swappedURL, withDestinationURL: outside)
        try FileManager.default.removeItem(at: fixture.folder.appendingPathComponent(removed.fileName))
        #expect(await library.fileURL(swapped.id) == nil)
        #expect(await library.fileURL(removed.id) == nil)
    }
}
#endif
