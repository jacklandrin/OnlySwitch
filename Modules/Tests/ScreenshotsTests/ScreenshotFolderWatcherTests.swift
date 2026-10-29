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

    @Test func missingFolderFinishesImmediately() async throws {
        let root = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let watcher = ScreenshotFolderWatcher(folder: root.appendingPathComponent("Missing", isDirectory: true))
        var iterator = watcher.events().makeAsyncIterator()
        #expect(await iterator.next() == nil)
        #expect(watcher.activeSessionCount == 0)
    }
}
#endif
