#if os(macOS)
import Foundation
import Testing
@testable import Screenshots

actor ScreenshotEventCollector {
    private(set) var urls: [URL] = []
    func append(_ url: URL) { urls.append(url) }
    var names: [String] { urls.map(\.lastPathComponent) }
}

/// Starts consuming before the caller touches the folder; the watcher snapshots existing files synchronously.
func collect(_ stream: AsyncStream<URL>) -> (ScreenshotEventCollector, Task<Void, Never>) {
    let collector = ScreenshotEventCollector()
    let task = Task { for await url in stream { await collector.append(url) } }
    return (collector, task)
}

/// Polls until `condition` holds or 2 seconds pass; returns whether it held.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

struct ScreenshotFolderWatcherTests {
    @Test func emitsRenamedFinalFileOnceAndIgnoresHiddenTemp() async throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let watcher = ScreenshotFolderWatcher(folder: folder)
        let (collector, task) = collect(watcher.events()); defer { task.cancel() }
        let temp = try writePNG(to: folder.appendingPathComponent(".Screenshot 2026-10-29 temp.png"))
        try await Task.sleep(for: .milliseconds(500))
        #expect(await collector.urls.isEmpty)
        let final = folder.appendingPathComponent("Screenshot 2026-10-29 at 10.00.00.png")
        try FileManager.default.moveItem(at: temp, to: final)
        #expect(await eventually { await collector.urls.count == 1 })
        try await Task.sleep(for: .milliseconds(500))
        #expect(await collector.urls.map(\.standardizedFileURL) == [final.standardizedFileURL])
    }

    @Test func ignoresNonImagesAndPreexistingFiles() async throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let old = try writePNG(to: folder.appendingPathComponent("Old.png"))
        let watcher = ScreenshotFolderWatcher(folder: folder)
        let (collector, task) = collect(watcher.events()); defer { task.cancel() }
        try Data("text".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        try Data("not an image".utf8).write(to: folder.appendingPathComponent("fake.png"))
        try writePNG(to: old, color: (0, 1, 0))
        try writePNG(to: folder.appendingPathComponent("New.png"))
        #expect(await eventually { await collector.urls.count == 1 })
        try await Task.sleep(for: .milliseconds(500))
        #expect(await collector.names == ["New.png"])
    }

    @Test func waitsUntilFileIsCompletelyWritten() async throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let watcher = ScreenshotFolderWatcher(folder: folder)
        let (collector, task) = collect(watcher.events()); defer { task.cancel() }
        let data = try pngData(width: 64, height: 64)
        let url = folder.appendingPathComponent("Partial.png")
        try data.prefix(data.count / 2).write(to: url)
        try await Task.sleep(for: .milliseconds(700))
        #expect(await collector.urls.isEmpty)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd(); try handle.write(contentsOf: data.suffix(from: data.count / 2)); try handle.close()
        #expect(await eventually { await collector.urls.count == 1 })
        try await Task.sleep(for: .milliseconds(300))
        #expect(await collector.names == ["Partial.png"])
    }

    @Test func cancellingConsumerStopsWatching() async throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let watcher = ScreenshotFolderWatcher(folder: folder)
        let (collector, task) = collect(watcher.events())
        #expect(await eventually { watcher.activeSessionCount == 1 })
        task.cancel()
        #expect(await eventually { watcher.activeSessionCount == 0 })
        try writePNG(to: folder.appendingPathComponent("After.png"))
        try await Task.sleep(for: .milliseconds(500))
        #expect(await collector.urls.isEmpty)
    }

    @Test func emitsSettledRecordingOnce() async throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = try await writeMovie(to: makeTemporaryDirectory().appendingPathComponent("r.mov"))
        let watcher = ScreenshotFolderWatcher(folder: folder)
        let (collector, task) = collect(watcher.events()); defer { task.cancel() }
        try FileManager.default.moveItem(at: source, to: folder.appendingPathComponent("Screen Recording 2026-11-07 at 10.00.00.mov"))
        #expect(await eventually { await collector.names == ["Screen Recording 2026-11-07 at 10.00.00.mov"] })
    }

    @Test func recordingThatPausesBeforeFinalisingIsStillEmitted() async throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let watcher = ScreenshotFolderWatcher(folder: folder, stabilityInterval: .milliseconds(5), stableChecks: 1)
        let (collector, task) = collect(watcher.events()); defer { task.cancel() }
        func box(_ type: String, _ payload: Data) -> Data { withUnsafeBytes(of: UInt32(payload.count + 8).bigEndian) { Data($0) } + Data(type.utf8) + payload }
        let url = folder.appendingPathComponent("Simulator Screen Recording.mov")
        try (box("ftyp", Data("qt  ".utf8) + Data(count: 4)) + box("mdat", Data(count: 64))).write(to: url)
        // Far more settled checks than an image is given before it is abandoned.
        try await Task.sleep(for: .milliseconds(800))
        #expect(await collector.urls.isEmpty)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd(); try handle.write(contentsOf: box("moov", Data(count: 8))); try handle.close()
        #expect(await eventually { await collector.names == ["Simulator Screen Recording.mov"] })
    }

    @Test func movieWithoutMoovBoxIsIncomplete() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        // ftyp + mdat only: what a recorder has written before finalising.
        var bytes = Data([0, 0, 0, 16]) + Data("ftypqt  ".utf8) + Data([0, 0, 0, 0])
        bytes += Data([0, 0, 0, 12]) + Data("mdat".utf8) + Data([1, 2, 3, 4])
        let partial = folder.appendingPathComponent("partial.mov"); try bytes.write(to: partial)
        #expect(ScreenshotFileCompleteness.isComplete(partial) == false)
    }

    @Test func finishedMovieIsComplete() async throws {
        let url = try await writeMovie(to: makeTemporaryDirectory().appendingPathComponent("done.mov"))
        #expect(ScreenshotFileCompleteness.isComplete(url))
    }

    @Test func moovAfterMdatIsCompleteAndMalformedSizesTerminate() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        func box(_ type: String, _ payload: Data) -> Data { withUnsafeBytes(of: UInt32(payload.count + 8).bigEndian) { Data($0) } + Data(type.utf8) + payload }
        let ftyp = box("ftyp", Data("qt  ".utf8) + Data(count: 4)), mdat = box("mdat", Data(count: 64))
        func check(_ bytes: Data) throws -> Bool { let url = folder.appendingPathComponent("\(UUID()).mov"); try bytes.write(to: url); return ScreenshotFileCompleteness.isComplete(url) }
        #expect(try check(ftyp + box("wide", Data()) + mdat + box("moov", Data(count: 8))))
        // A moov whose declared size runs past the end is still being written.
        #expect(try check(ftyp + mdat + box("moov", Data(count: 8)).dropLast(2)) == false)
        // Zero, sub-header and overflowing 64-bit sizes must stop the walk instead of looping or trapping.
        #expect(try check(Data([0, 0, 0, 4]) + Data("mdat".utf8) + box("moov", Data())) == false)
        #expect(try check(Data([0, 0, 0, 0]) + Data("mdat".utf8) + box("moov", Data())) == false)
        #expect(try check(Data([0, 0, 0, 1]) + Data("mdat".utf8) + Data(repeating: 0xFF, count: 8) + box("moov", Data())) == false)
        #expect(try check(Data([0, 0, 0, 1]) + Data("mdat".utf8) + Data(count: 8) + box("moov", Data())) == false)
    }

    @Test func missingFolderFinishesImmediately() async throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let watcher = ScreenshotFolderWatcher(folder: root.appendingPathComponent("Missing", isDirectory: true))
        var iterator = watcher.events().makeAsyncIterator()
        #expect(await iterator.next() == nil)
        #expect(watcher.activeSessionCount == 0)
    }
}
#endif
