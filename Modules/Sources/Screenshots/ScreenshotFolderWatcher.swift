#if os(macOS)
import Darwin
import Foundation
import ImageIO

/// Watches one directory and emits each new, visible image or movie file once its size has settled and it is
/// complete (see `ScreenshotFileCompleteness`). Files present when `events()` is called are never emitted.
/// `screencaptureui` writes a hidden temp file and renames it, so only the final name is reported.
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
    private struct Pending { var size: Int64 = -1; var stableCount = 0; var invalidChecks = 0; let maxInvalidChecks: Int }
    /// Stop retrying a settled file that never decodes (e.g. a non-image with an image extension).
    private static let maxInvalidImageChecks = 40
    /// A recorder written straight to its final name can pause for minutes before it adds the `moov` box,
    /// so a movie keeps being checked (a few header reads) for about 10 minutes at the default interval.
    private static let maxInvalidRecordingChecks = 4_000
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
        for name in current.subtracting(known) where !name.hasPrefix(".") && ScreenshotLibrary.isMediaName(name) {
            let isRecording = ScreenshotMediaType(fileName: name) == .recording
            pending[name] = Pending(maxInvalidChecks: isRecording ? Self.maxInvalidRecordingChecks : Self.maxInvalidImageChecks)
        }
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
                if ScreenshotFileCompleteness.isComplete(url) { pending[name] = nil; continuation.yield(url); continue }
                state.invalidChecks += 1
                if state.invalidChecks >= state.maxInvalidChecks { pending[name] = nil; continue }
            }
            pending[name] = state
        }
        schedulePoll()
    }

    private static func names(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }
}

/// Whether a settled file is safe to record: images must decode completely; movies must contain a complete
/// top-level `moov` box (written when the recorder finalises the file, usually after `mdat`).
enum ScreenshotFileCompleteness {
    static func isComplete(_ url: URL) -> Bool {
        switch ScreenshotMediaType(fileName: url.lastPathComponent) {
        case .image: isCompleteImage(url)
        case .recording: hasMovieBox(url)
        case nil: false
        }
    }

    /// Walks the top-level ISO-BMFF / QuickTime boxes; a size of 1 means a 64-bit size follows, 0 means "to end".
    /// Sizes below the header length or past the end of the file stop the walk.
    static func hasMovieBox(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return false }
        var offset: UInt64 = 0
        while end - offset >= 8 {
            guard (try? handle.seek(toOffset: offset)) != nil, let header = try? handle.read(upToCount: 16), header.count >= 8 else { return false }
            var size = header.prefix(4).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }, headerSize: UInt64 = 8
            let type = String(decoding: header[4..<8], as: UTF8.self)
            if size == 1 {
                guard header.count == 16 else { return false }
                size = header[8..<16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }; headerSize = 16
            } else if size == 0 { size = end - offset }
            guard size >= headerSize, size <= end - offset else { return false }
            if type == "moov" { return true }
            offset += size
        }
        return false
    }

    /// ImageIO treats a file source as final and happily decodes a truncated PNG/JPEG, so those formats must
    /// also end with their terminator (PNG `IEND` chunk, JPEG EOI marker).
    static func isCompleteImage(_ url: URL) -> Bool {
        guard hasTerminator(url) else { return false }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0, CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil
    }

    private static let pngTrailer: [UInt8] = [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
    private static let jpegTrailer: [UInt8] = [0xFF, 0xD9]

    static func hasTerminator(_ url: URL) -> Bool {
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
