import Foundation
import RemoteCore
import RemoteTransport

typealias RemoteHandshake = RemoteHandshakeCrypto

enum RemotePairingCommitStage: Equatable, Sendable {
    case afterFinalize
    case duringLifecycleCommit
    case afterLifecycleCommit
    case beforeHostAuthentication
}

struct RemotePairingTransaction: Sendable {
    let record: PairedRemoteDevice
    let previous: PairedRemoteDevice?
    let snapshot: RemotePairingSnapshot

    static func begin(
        record: PairedRemoteDevice,
        credentialStore: RemoteCredentialStore,
        pairingSnapshot: @escaping @Sendable (UUID) async -> RemotePairingSnapshot?,
        consumePairing: @escaping @Sendable () async -> Bool
    ) async throws -> Self {
        guard let snapshot = await pairingSnapshot(record.id) else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing was superseded")
        }
        let previous = try await credentialStore.load(record.id)
        guard await consumePairing() else {
            throw RemoteProtocolError(code: .pairingExpired, message: "Pairing code expired")
        }
        try await credentialStore.save(record)
        return Self(record: record, previous: previous, snapshot: snapshot)
    }

    func validate(
        _ validate: @escaping @Sendable (RemotePairingSnapshot) async -> Bool
    ) async -> Bool {
        await validate(snapshot)
    }

    func commit(
        _ commit: @escaping @Sendable (RemotePairingSnapshot) async -> Bool
    ) async -> Bool {
        await commit(snapshot)
    }

    func rollback(
        credentialStore: RemoteCredentialStore,
        rollbackPairingState: @escaping @Sendable (RemotePairingSnapshot) async -> Bool,
        currentEpoch: @escaping @Sendable (UUID) async -> UInt64
    ) async {
        let restorePrevious = await rollbackPairingState(snapshot)
        try? await credentialStore.rollbackReplacement(
            record,
            previous: previous,
            restorePrevious: restorePrevious
        )
        if restorePrevious,
           await currentEpoch(record.id) != snapshot.epoch,
           let previous {
            try? await credentialStore.delete(record.id, matchingCredential: previous.credential)
        }
    }
}
