#if os(macOS)
import AppKit
import Dependencies
import ImageIO

/// Every file-system, pasteboard, workspace and system-settings effect of the Screenshots tab. Files are
/// addressed by recorded item id only; `fileURL` is the single way to turn an id into a path.
public struct ScreenshotsClient: Sendable {
    public var folderURL: @Sendable () -> URL
    public var load: @Sendable () async throws -> [ScreenshotItem]
    /// Items already persisted by the library. A single subscriber (the shared store) is expected.
    public var captures: @Sendable () -> AsyncStream<ScreenshotItem>
    public var setPinned: @Sendable (UUID, Bool) async throws -> [ScreenshotItem]
    public var trash: @Sendable ([UUID]) async -> (items: [ScreenshotItem], failures: [ScreenshotFailure])
    public var replaceImage: @Sendable (UUID, Data) async throws -> [ScreenshotItem]
    public var fileURL: @Sendable (UUID) async -> URL?
    /// url, maxPixel, revision (cache key).
    public var thumbnail: @Sendable (URL, Int, Int) async -> CGImage?
    public var captureStatus: @Sendable () async -> ScreenshotCaptureStatus
    public var enableCapture: @Sendable () async throws -> Void
    public var disableCapture: @Sendable () async throws -> Void
    public var copyToPasteboard: @MainActor @Sendable (URL) -> Bool
    public var openInDefaultApp: @MainActor @Sendable (URL) -> Void
    public var revealFolder: @MainActor @Sendable () -> Void

    public init(
        folderURL: @escaping @Sendable () -> URL,
        load: @escaping @Sendable () async throws -> [ScreenshotItem],
        captures: @escaping @Sendable () -> AsyncStream<ScreenshotItem>,
        setPinned: @escaping @Sendable (UUID, Bool) async throws -> [ScreenshotItem],
        trash: @escaping @Sendable ([UUID]) async -> (items: [ScreenshotItem], failures: [ScreenshotFailure]),
        replaceImage: @escaping @Sendable (UUID, Data) async throws -> [ScreenshotItem],
        fileURL: @escaping @Sendable (UUID) async -> URL?,
        thumbnail: @escaping @Sendable (URL, Int, Int) async -> CGImage?,
        captureStatus: @escaping @Sendable () async -> ScreenshotCaptureStatus,
        enableCapture: @escaping @Sendable () async throws -> Void,
        disableCapture: @escaping @Sendable () async throws -> Void,
        copyToPasteboard: @escaping @MainActor @Sendable (URL) -> Bool,
        openInDefaultApp: @escaping @MainActor @Sendable (URL) -> Void,
        revealFolder: @escaping @MainActor @Sendable () -> Void
    ) {
        self.folderURL = folderURL; self.load = load; self.captures = captures; self.setPinned = setPinned; self.trash = trash
        self.replaceImage = replaceImage; self.fileURL = fileURL; self.thumbnail = thumbnail; self.captureStatus = captureStatus
        self.enableCapture = enableCapture; self.disableCapture = disableCapture; self.copyToPasteboard = copyToPasteboard
        self.openInDefaultApp = openInDefaultApp; self.revealFolder = revealFolder
    }
}

extension ScreenshotsClient: DependencyKey {
    public static let liveValue: Self = {
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        return live(folder: home.appendingPathComponent("Pictures/OnlySwitch Screenshots", isDirectory: true), manifestURL: support.appendingPathComponent("OnlySwitch/Screenshots/library.json"))
    }()

    static func live(folder: URL, manifestURL: URL) -> Self {
        let library = ScreenshotLibrary(folder: folder, manifestURL: manifestURL, trash: { url in _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil) }, now: { Date() }, uuid: { UUID() })
        let watcher = ScreenshotFolderWatcher(folder: folder)
        let thumbnails = ScreenshotThumbnailCache()
        let preferences = ScreenCapturePreferences.live(folder: folder)
        return Self(
            folderURL: { folder },
            load: {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                return try await library.load()
            },
            captures: {
                // The watcher can only open an existing folder, so create it before subscribing.
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let events = watcher.events()
                return AsyncStream { continuation in
                    let task = Task {
                        for await url in events {
                            if let item = try? await library.add(fileURL: url) { continuation.yield(item) }
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            setPinned: { try await library.setPinned($0, $1) },
            trash: { ids in
                let (items, failures) = await library.trash(ids)
                return (items: items, failures: failures)
            },
            replaceImage: { try await library.replaceImage($0, data: $1) },
            fileURL: { await library.fileURL($0) },
            thumbnail: { url, maxPixel, revision in thumbnails.thumbnail(for: url, maxPixel: maxPixel, revision: revision) },
            captureStatus: { preferences.status(enabledFlag: preferences.isEnabled) },
            enableCapture: { try preferences.enable() },
            disableCapture: { try preferences.disable() },
            copyToPasteboard: { url in
                guard let image = NSImage(contentsOf: url) else { return false }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                return pasteboard.writeObjects([url as NSURL, image])
            },
            openInDefaultApp: { url in NSWorkspace.shared.open(url) },
            revealFolder: { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
        )
    }

    public static let testValue = Self(
        folderURL: { reportIssue("Unimplemented: ScreenshotsClient.folderURL"); return URL(fileURLWithPath: NSTemporaryDirectory()) },
        load: { reportIssue("Unimplemented: ScreenshotsClient.load"); return [] },
        captures: { reportIssue("Unimplemented: ScreenshotsClient.captures"); return AsyncStream { $0.finish() } },
        setPinned: { _, _ in reportIssue("Unimplemented: ScreenshotsClient.setPinned"); return [] },
        trash: { _ in reportIssue("Unimplemented: ScreenshotsClient.trash"); return (items: [], failures: []) },
        replaceImage: { _, _ in reportIssue("Unimplemented: ScreenshotsClient.replaceImage"); return [] },
        fileURL: { _ in reportIssue("Unimplemented: ScreenshotsClient.fileURL"); return nil },
        thumbnail: { _, _, _ in reportIssue("Unimplemented: ScreenshotsClient.thumbnail"); return nil },
        captureStatus: { reportIssue("Unimplemented: ScreenshotsClient.captureStatus"); return .disabled },
        enableCapture: { reportIssue("Unimplemented: ScreenshotsClient.enableCapture") },
        disableCapture: { reportIssue("Unimplemented: ScreenshotsClient.disableCapture") },
        copyToPasteboard: { _ in reportIssue("Unimplemented: ScreenshotsClient.copyToPasteboard"); return false },
        openInDefaultApp: { _ in reportIssue("Unimplemented: ScreenshotsClient.openInDefaultApp") },
        revealFolder: { reportIssue("Unimplemented: ScreenshotsClient.revealFolder") }
    )
}

/// App-side presentation the package cannot own: revealing a list host, the fly-in overlay and the editor
/// window. The package's live value is `.noop`; the app injects its implementation when building the store.
public struct ScreenshotPresentationClient: Sendable {
    /// Ask the app to show a list host on the Screenshots section. Returns false when the tab is hidden.
    public var revealScreenshotsSection: @MainActor @Sendable () -> Bool
    /// Animate `url` from screen center into `target` (screen coordinates). Returns when landed.
    public var flyIn: @MainActor @Sendable (_ url: URL, _ target: CGRect) async -> Void
    public var openEditor: @MainActor @Sendable (_ itemID: UUID) -> Void
    public var reduceMotion: @MainActor @Sendable () -> Bool

    public init(
        revealScreenshotsSection: @escaping @MainActor @Sendable () -> Bool,
        flyIn: @escaping @MainActor @Sendable (_ url: URL, _ target: CGRect) async -> Void,
        openEditor: @escaping @MainActor @Sendable (_ itemID: UUID) -> Void,
        reduceMotion: @escaping @MainActor @Sendable () -> Bool
    ) {
        self.revealScreenshotsSection = revealScreenshotsSection; self.flyIn = flyIn; self.openEditor = openEditor; self.reduceMotion = reduceMotion
    }

    /// Never reveals, never animates, never opens a window.
    public static let noop = Self(revealScreenshotsSection: { false }, flyIn: { _, _ in }, openEditor: { _ in }, reduceMotion: { false })
}

extension ScreenshotPresentationClient: DependencyKey {
    public static let liveValue = Self.noop
    public static let testValue = Self(
        revealScreenshotsSection: { reportIssue("Unimplemented: ScreenshotPresentationClient.revealScreenshotsSection"); return false },
        flyIn: { _, _ in reportIssue("Unimplemented: ScreenshotPresentationClient.flyIn") },
        openEditor: { _ in reportIssue("Unimplemented: ScreenshotPresentationClient.openEditor") },
        reduceMotion: { reportIssue("Unimplemented: ScreenshotPresentationClient.reduceMotion"); return false }
    )
}

public extension DependencyValues {
    var screenshotsClient: ScreenshotsClient { get { self[ScreenshotsClient.self] } set { self[ScreenshotsClient.self] = newValue } }
    var screenshotPresentationClient: ScreenshotPresentationClient { get { self[ScreenshotPresentationClient.self] } set { self[ScreenshotPresentationClient.self] = newValue } }
}

/// `@unchecked Sendable`: the only stored property is an `NSCache`, which is documented as thread-safe.
final class ScreenshotThumbnailCache: @unchecked Sendable {
    private let cache = NSCache<NSString, CGImage>()
    init() { cache.countLimit = 200 }

    func thumbnail(for url: URL, maxPixel: Int, revision: Int) -> CGImage? {
        let key = "\(url.path)#\(revision)#\(maxPixel)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
#endif
