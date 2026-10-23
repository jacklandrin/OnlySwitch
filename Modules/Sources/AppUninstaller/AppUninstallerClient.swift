#if os(macOS)
import AppKit
import Dependencies
import UniformTypeIdentifiers

public struct AppUninstallerClient: Sendable {
    public var scan: @Sendable (URL) async throws -> UninstallerSnapshot
    public var remove: @Sendable (UninstallerRemovalRequest) async throws -> UninstallerRemovalResult
    public var activateSnapshot: @Sendable (UUID) async -> Void
    public var chooseApplication: @MainActor @Sendable () async -> URL?
    public var openPrivacySettings: @MainActor @Sendable () -> Void
    public init(scan: @escaping @Sendable (URL) async throws -> UninstallerSnapshot, remove: @escaping @Sendable (UninstallerRemovalRequest) async throws -> UninstallerRemovalResult, activateSnapshot: @escaping @Sendable (UUID) async -> Void = { _ in }, chooseApplication: @escaping @MainActor @Sendable () async -> URL? = { nil }, openPrivacySettings: @escaping @MainActor @Sendable () -> Void = {}) {
        self.scan = scan; self.remove = remove; self.activateSnapshot = activateSnapshot; self.chooseApplication = chooseApplication; self.openPrivacySettings = openPrivacySettings
    }
}
extension AppUninstallerClient: DependencyKey {
    public static let liveValue: Self = {
        let filesystem = AppUninstallerFileSystem(home: FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath(), selfApplicationURL: Bundle.main.bundleURL.resolvingSymlinksInPath(), selfBundleIdentifier: Bundle.main.bundleIdentifier, runningApplicationURLs: {
            await MainActor.run { NSWorkspace.shared.runningApplications.compactMap(\.bundleURL) }
        }, trash: { url in _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil) })
        return Self(scan: { try await filesystem.scan($0) }, remove: { try await filesystem.remove($0) }, activateSnapshot: { await filesystem.activateSnapshot($0) }, chooseApplication: {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false; panel.canChooseFiles = true
            return await panel.begin() == .OK ? panel.url : nil
        }, openPrivacySettings: {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
        })
    }()
    public static let testValue = Self(scan: { _ in throw UninstallerFailure(key: "App Uninstaller Scan Failed") }, remove: { _ in .init() })
}
public extension DependencyValues {
    var appUninstallerClient: AppUninstallerClient { get { self[AppUninstallerClient.self] } set { self[AppUninstallerClient.self] = newValue } }
}
#endif
