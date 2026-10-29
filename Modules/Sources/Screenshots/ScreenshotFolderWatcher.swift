#if os(macOS)
import Darwin
import Foundation
import ImageIO

/// Watches one directory and emits each new, visible image file once its size has settled and ImageIO can
/// read a complete image. Files present when `events()` is called are never emitted. `screencaptureui`
/// writes a hidden temp file and renames it, so only the final name is reported.
public final class ScreenshotFolderWatcher: Sendable {
    public let folder: URL
    private let stabilityInterval: Duration
    private let stableChecks: Int
    private let sessions = ScreenshotWatcherSessionCounter()

    public init(folder: URL, stabilityInterval: Duration = .milliseconds(150), stableChecks: Int = 2) {
        self.folder = folder; self.stabilityInterval = stabilityInterval; self.stableChecks = max(1, stableChecks)
    }

    /// Number of live directory sources; exposed for tests that verify cancellation releases the descriptor.
    var activeSessionCount: Int { sessions.value }

    /// Each call starts an independent session. The existing contents are snapshotted before returning; the
    /// stream finishes immediately when the folder cannot be opened. Cancelling the consumer stops watching.
    public func events() -> AsyncStream<URL> {
        let (stream, continuation) = AsyncStream.makeStream(of: URL.self)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { continuation.finish(); return stream }
        let session = ScreenshotWatcherSession(folder: folder, descriptor: descriptor, interval: stabilityInterval, stableChecks: stableChecks, continuation: continuation, counter: sessions)
        continuation.onTermination = { _ in session.stop() }
        session.start()
        return stream
    }
}

/// Lock-guarded counter; the only state shared between sessions and the watcher.
final class ScreenshotWatcherSessionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func add(_ delta: Int) { lock.lock(); defer { lock.unlock() }; count += delta }
}

/// `@unchecked Sendable`: every mutable property is read and written only on `queue` (a private serial
/// queue that also runs the dispatch source handlers), except the immutable configuration set in `init`.
private final class ScreenshotWatcherSession: @unchecked Sendable {
    private struct Pending { var size: Int64 = -1; var stableCount = 0; var invalidChecks = 0 }
    /// Stop retrying a settled file that never decodes (e.g. a non-image with an image extension).
    private static let maxInvalidChecks = 40
    private let folder: URL
    private let interval: DispatchTimeInterval
    private let stableChecks: Int
    private let continuation: AsyncStream<URL>.Continuation
    private let counter: ScreenshotWatcherSessionCounter
    private let queue = DispatchQueue(label: "OnlySwitch.ScreenshotFolderWatcher")
    private let source: DispatchSourceFileSystemObject
    private var known: Set<String>
    private var pending: [String: Pending] = [:]
    private var isPolling = false
    private var isStopped = false

    init(folder: URL, descriptor: Int32, interval: Duration, stableChecks: Int, continuation: AsyncStream<URL>.Continuation, counter: ScreenshotWatcherSessionCounter) {
        self.folder = folder; self.stableChecks = stableChecks; self.continuation = continuation; self.counter = counter
        let (seconds, attoseconds) = interval.components
        self.interval = .nanoseconds(Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000))
        self.known = Self.names(in: folder)
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: queue)
        source.setCancelHandler { close(descriptor) }
    }

    func start() {
        counter.add(1)
        source.setEventHandler { [weak self] in self?.scan() }
        source.resume()
    }

    func stop() {
        queue.async { [self] in
            guard !isStopped else { return }
            isStopped = true
            pending.removeAll()
            source.cancel()
            counter.add(-1)
        }
    }

    private func scan() {
        guard !isStopped else { return }
        let current = Self.names(in: folder)
        for name in current.subtracting(known) where !name.hasPrefix(".") && ScreenshotLibrary.isImageName(name) { pending[name] = Pending() }
        for name in pending.keys where !current.contains(name) { pending[name] = nil }
        known = current
        schedulePoll()
    }

    private func schedulePoll() {
        guard !isPolling, !pending.isEmpty, !isStopped else { return }
        isPolling = true
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in self?.poll() }
    }

    private func poll() {
        isPolling = false
        guard !isStopped else { return }
        for (name, var state) in pending {
            let url = folder.appendingPathComponent(name)
            guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 else { pending[name] = nil; continue }
            if size > 0, size == state.size { state.stableCount += 1 } else { state.stableCount = 0; state.size = size; state.invalidChecks = 0 }
            if state.stableCount >= stableChecks {
                if Self.isCompleteImage(url) { pending[name] = nil; continuation.yield(url); continue }
                state.invalidChecks += 1
                if state.invalidChecks >= Self.maxInvalidChecks { pending[name] = nil; continue }
            }
            pending[name] = state
        }
        schedulePoll()
    }

    private static func names(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    /// ImageIO treats a file source as final and happily decodes a truncated PNG/JPEG, so those formats must
    /// also end with their terminator (PNG `IEND` chunk, JPEG EOI marker).
    private static func isCompleteImage(_ url: URL) -> Bool {
        guard hasTerminator(url) else { return false }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0, CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil
    }

    private static let pngTrailer: [UInt8] = [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
    private static let jpegTrailer: [UInt8] = [0xFF, 0xD9]

    private static func hasTerminator(_ url: URL) -> Bool {
        let trailer: [UInt8]
        switch url.pathExtension.lowercased() {
        case "png": trailer = pngTrailer
        case "jpg", "jpeg": trailer = jpegTrailer
        default: return true
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end >= UInt64(trailer.count) else { return false }
        do {
            try handle.seek(toOffset: end - UInt64(trailer.count))
            return try handle.read(upToCount: trailer.count).map(Array.init) == trailer
        } catch { return false }
    }
}
#endif
