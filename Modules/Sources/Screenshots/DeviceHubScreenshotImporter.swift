#if os(macOS)
import Darwin
import Foundation

/// Xcode's Device Hub (`com.apple.dt.Devices`) keeps its screenshot location in its sandbox container, which other
/// apps cannot change, so it always saves to the Desktop. While collection is on, new images there whose quarantine
/// agent is DeviceHub are moved into the library folder, where the library watcher records them. Files already on
/// the Desktop when watching starts, and files from any other app, are never touched.
public struct DeviceHubScreenshotImporter: Sendable {
    static let quarantineAgent = "DeviceHub"
    public let source: URL
    public let destination: URL
    private let stabilityInterval: Duration

    public init(source: URL, destination: URL, stabilityInterval: Duration = .milliseconds(150)) {
        self.source = source; self.destination = destination; self.stabilityInterval = stabilityInterval
    }

    /// Runs until cancelled, or returns at once when the source folder cannot be opened (e.g. Desktop access denied).
    public func run() async {
        let watcher = ScreenshotFolderWatcher(folder: source, stabilityInterval: stabilityInterval)
        for await url in watcher.events() where Self.isDeviceHubCapture(url) {
            _ = try? move(url)
        }
    }

    /// The quarantine value is `flags;timestamp;agent;uuid`; only the agent field is compared.
    static func isDeviceHubCapture(_ url: URL) -> Bool {
        let name = "com.apple.quarantine"
        let size = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return false }
        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(url.path, name, &buffer, size, 0, XATTR_NOFOLLOW) == size else { return false }
        let fields = String(decoding: buffer, as: UTF8.self).split(separator: ";", omittingEmptySubsequences: false)
        return fields.count > 2 && fields[2] == Self.quarantineAgent
    }

    /// Moves into the destination, appending " 2", " 3", … instead of replacing an existing file.
    func move(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var target = destination.appendingPathComponent(url.lastPathComponent)
        var index = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = destination.appendingPathComponent(ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)")
            index += 1
        }
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }
}
#endif
