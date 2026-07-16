import Dependencies
import DependenciesMacros
import Foundation
import RemoteCore

struct RemoteConnectionSnapshot: Equatable, Sendable {
    var selectedMacID: UUID?
    var authenticatedMacID: UUID?
    var authenticatedSessionID: UUID?

    init(
        selectedMacID: UUID? = nil,
        authenticatedMacID: UUID? = nil,
        authenticatedSessionID: UUID? = nil
    ) {
        self.selectedMacID = selectedMacID
        self.authenticatedMacID = authenticatedMacID
        self.authenticatedSessionID = authenticatedSessionID
    }
}

struct RemoteActionInvocation: Equatable, Sendable {
    let macID: UUID
    let sessionID: UUID
    let request: RemoteActionRequest
}

enum RemotePairAdoptionResult: Equatable, Sendable {
    case authenticated
    case connecting
    case offline
}

@DependencyClient
struct RemoteConnectionClient: Sendable {
    var discover: @Sendable () -> AsyncStream<DiscoveryEvent> = { AsyncStream { $0.finish() } }
    var pair: @Sendable (DiscoveredMac, String, String) async throws -> PairedMac = { _, _, _ in throw RemoteDependencyError.unimplemented }
    var cancelPairing: @Sendable () async -> Void = {}
    var select: @Sendable (PairedMac?) async -> Void = { _ in }
    var events: @Sendable () -> AsyncStream<RemoteConnectionEvent> = { AsyncStream { $0.finish() } }
    var snapshot: @Sendable () async -> RemoteConnectionSnapshot = { .init() }
    var adoptPairedMac: @Sendable (PairedMac) async -> RemotePairAdoptionResult = { _ in .offline }
    var forgetMac: @Sendable (UUID) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var subscribe: @Sendable (Set<RemoteControlID>) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var send: @Sendable (RemoteActionInvocation) async throws -> RemoteActionResult = { _ in throw RemoteDependencyError.unimplemented }
    var setForegrounded: @Sendable (Bool) async -> Void = { _ in }
}

extension RemoteConnectionClient: DependencyKey {
    static var liveValue: Self { .live }
    static var testValue: Self {
        var value = Self()
        value.cancelPairing = {}
        value.events = { AsyncStream { $0.finish() } }
        value.snapshot = { .init() }
        value.adoptPairedMac = { _ in .offline }
        return value
    }
}

extension DependencyValues {
    var remoteConnection: RemoteConnectionClient {
        get { self[RemoteConnectionClient.self] }
        set { self[RemoteConnectionClient.self] = newValue }
    }
}
