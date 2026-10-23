#if os(macOS)
import Foundation
import Testing
@testable import AppUninstaller

struct UninstallerFixture {
    let home: URL
    var applicationURL: URL { url("Applications/Example.app") }
    init() throws {
        home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("OnlySwitchUninstallerTests-\(UUID().uuidString)")
        try makeApplication()
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
    func url(_ path: String) -> URL { home.appendingPathComponent(path) }
    @discardableResult func write(_ path: String) throws -> URL {
        let target = url(path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: target)
        return target
    }
    func makeApplication(identifier: String = "org.example.Editor") throws {
        let contents = applicationURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundleName": "Example", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
    }
    func makeFileSystem(sink: UninstallerTrashSink = .init(), running: UninstallerRunningApps = .init(), selfURL: URL? = nil) -> AppUninstallerFileSystem {
        AppUninstallerFileSystem(home: home, selfApplicationURL: selfURL ?? url("Applications/OnlySwitch.app"), runningApplicationURLs: { await running.urls }, trash: { try sink.trash($0) })
    }
    func applicationItem(in snapshot: UninstallerSnapshot) throws -> UninstallerItem {
        try #require(snapshot.items.first { $0.kind == .application })
    }
}

// Records only fixture URLs. No test invokes the user's Trash or removes an installed application.
final class UninstallerTrashSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    let failingName: String?
    init(failingName: String? = nil) { self.failingName = failingName }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
    func trash(_ url: URL) throws {
        if url.lastPathComponent == failingName { throw CocoaError(.fileWriteNoPermission) }
        lock.lock(); defer { lock.unlock() }; storage.append(url)
    }
}
actor UninstallerRunningApps {
    var urls: [URL] = []
    func set(_ urls: [URL]) { self.urls = urls }
}
actor UninstallerRequestRecorder {
    var requests: [UninstallerRemovalRequest] = []
    var activations: [UUID] = []
    func record(_ request: UninstallerRemovalRequest) { requests.append(request) }
    func activate(_ id: UUID) { activations.append(id) }
}
func uninstallerSnapshot() -> UninstallerSnapshot {
    let app = URL(fileURLWithPath: "/fixture/Example.app")
    return UninstallerSnapshot(id: UUID(), applicationURL: app, bundleIdentifier: "org.example.Editor", displayName: "Example", items: [
        UninstallerItem(id: "app", url: app, kind: .application, bytes: 100),
        UninstallerItem(id: "preferences", url: URL(fileURLWithPath: "/fixture/Library/Preferences/org.example.Editor.plist"), kind: .preferences, bytes: 10)
    ], failures: [])
}
#endif
