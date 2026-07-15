import Dependencies
import DependenciesMacros
import Foundation
import RemoteCore

@DependencyClient
struct RemoteConnectionClient: Sendable {
    var discover: @Sendable () -> AsyncStream<DiscoveryEvent> = { AsyncStream { $0.finish() } }
    var pair: @Sendable (DiscoveredMac, String, String) async throws -> PairedMac = { _, _, _ in throw RemoteDependencyError.unimplemented }
    var select: @Sendable (PairedMac?) async -> Void = { _ in }
    var events: @Sendable () -> AsyncStream<RemoteConnectionEvent> = { AsyncStream { $0.finish() } }
    var subscribe: @Sendable (Set<RemoteControlID>) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var send: @Sendable (RemoteActionRequest) async throws -> RemoteActionResult = { _ in throw RemoteDependencyError.unimplemented }
    var setForegrounded: @Sendable (Bool) async -> Void = { _ in }
}

extension RemoteConnectionClient: DependencyKey {
    static var liveValue: Self { .live }
    static var testValue: Self { Self() }
}

extension DependencyValues {
    var remoteConnection: RemoteConnectionClient {
        get { self[RemoteConnectionClient.self] }
        set { self[RemoteConnectionClient.self] = newValue }
    }
}
