#if os(macOS)
import AppKit
import Dependencies

public struct TailscaleClient: Sendable {
    public var snapshot: @Sendable () async throws -> TailscaleSnapshot
    public var perform: @Sendable (TailscaleOperation) async throws -> Void
    public var waitForIdle: @Sendable () async -> Void
    public var openApplication: @MainActor @Sendable () -> Void
    public var openDownload: @MainActor @Sendable () -> Void
    public init(snapshot: @escaping @Sendable () async throws -> TailscaleSnapshot, perform: @escaping @Sendable (TailscaleOperation) async throws -> Void, waitForIdle: @escaping @Sendable () async -> Void = {}, openApplication: @escaping @MainActor @Sendable () -> Void = {}, openDownload: @escaping @MainActor @Sendable () -> Void = {}) {
        self.snapshot = snapshot; self.perform = perform; self.waitForIdle = waitForIdle; self.openApplication = openApplication; self.openDownload = openDownload
    }
}

extension TailscaleClient: DependencyKey {
    public static let liveValue: Self = {
        let coordinator = TailscaleCoordinator()
        return Self(snapshot: { try await coordinator.snapshot() }, perform: { try await coordinator.perform($0) }, waitForIdle: { await coordinator.waitForIdle() }, openApplication: {
            let workspace = NSWorkspace.shared
            if let app = workspace.urlForApplication(withBundleIdentifier: "io.tailscale.ipn.macsys") ?? workspace.urlForApplication(withBundleIdentifier: "io.tailscale.ipn.macos") {
                workspace.openApplication(at: app, configuration: .init())
            } else if FileManager.default.fileExists(atPath: "/Applications/Tailscale.app") {
                workspace.open(URL(fileURLWithPath: "/Applications/Tailscale.app"))
            } else if let url = URL(string: "https://tailscale.com/download/mac") { workspace.open(url) }
        }, openDownload: {
            if let url = URL(string: "https://tailscale.com/download/mac") { NSWorkspace.shared.open(url) }
        })
    }()
    public static let testValue = Self(snapshot: { throw TailscaleError.unavailable }, perform: { _ in throw TailscaleError.unavailable })
}
public extension DependencyValues {
    var tailscaleClient: TailscaleClient { get { self[TailscaleClient.self] } set { self[TailscaleClient.self] = newValue } }
}
#endif
