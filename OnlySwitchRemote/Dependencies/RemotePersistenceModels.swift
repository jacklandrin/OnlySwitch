import CryptoKit
import Foundation

struct RemoteAppPersistenceIntent: Equatable, Sendable {
    let writerID: UUID
    let sequence: UInt64
    let selectedMacID: UUID?
    let hasCompletedInitialSetup: Bool
}

struct RemotePairingPersistenceSnapshot: Equatable, Sendable {
    let previousMac: PairedMac?
    let previousSelectedMacID: UUID?
    let wasTombstoned: Bool
}

struct RemotePersistentStateEnvelope: Codable, Equatable, Sendable {
    var version: Int = 1
    var pairedMacs: [PairedMac]
    var selectedMacID: UUID?
    var hasCompletedInitialSetup: Bool
    var tombstonedMacIDs: Set<UUID> = []
    var preparedPairing: PreparedPairingPersistenceRecord? = nil

    init(
        pairedMacs: [PairedMac],
        selectedMacID: UUID?,
        hasCompletedInitialSetup: Bool,
        tombstonedMacIDs: Set<UUID> = [],
        preparedPairing: PreparedPairingPersistenceRecord? = nil
    ) {
        self.pairedMacs = pairedMacs
        self.selectedMacID = selectedMacID
        self.hasCompletedInitialSetup = hasCompletedInitialSetup
        self.tombstonedMacIDs = tombstonedMacIDs
        self.preparedPairing = preparedPairing
    }
}

struct RemotePairingRollbackState: Codable, Equatable, Sendable {
    let pairedMacs: [PairedMac]
    let selectedMacID: UUID?
    let hasCompletedInitialSetup: Bool
    let tombstonedMacIDs: Set<UUID>
}

enum PreparedPairingPhase: String, Codable, Equatable, Sendable { case prepared, adopted }

struct PreparedPairingPersistenceRecord: Codable, Equatable, Sendable {
    let transactionID: UUID
    let candidate: PairedMac
    let candidateCredentialVerifier: Data
    var phase: PreparedPairingPhase
    let previous: RemotePairingRollbackState

    var candidateCredentialIdentity: Data { candidateCredentialVerifier }

    init(
        transactionID: UUID,
        candidate: PairedMac,
        candidateCredentialVerifier: Data,
        phase: PreparedPairingPhase = .prepared,
        previous: RemotePairingRollbackState
    ) {
        self.transactionID = transactionID
        self.candidate = candidate
        self.candidateCredentialVerifier = candidateCredentialVerifier
        self.phase = phase
        self.previous = previous
    }

    private enum CodingKeys: String, CodingKey {
        case transactionID, candidate, candidateCredentialVerifier, candidateCredentialIdentity, phase, previous
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactionID = try container.decode(UUID.self, forKey: .transactionID)
        candidate = try container.decode(PairedMac.self, forKey: .candidate)
        if let verifier = try container.decodeIfPresent(Data.self, forKey: .candidateCredentialVerifier) {
            candidateCredentialVerifier = verifier
        } else {
            let legacyRaw = try container.decode(Data.self, forKey: .candidateCredentialIdentity)
            candidateCredentialVerifier = Data(SHA256.hash(data: legacyRaw))
        }
        phase = try container.decodeIfPresent(PreparedPairingPhase.self, forKey: .phase) ?? .prepared
        previous = try container.decode(RemotePairingRollbackState.self, forKey: .previous)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transactionID, forKey: .transactionID)
        try container.encode(candidate, forKey: .candidate)
        try container.encode(candidateCredentialVerifier, forKey: .candidateCredentialVerifier)
        try container.encode(phase, forKey: .phase)
        try container.encode(previous, forKey: .previous)
    }

    init(
        transactionID: UUID,
        candidate: PairedMac,
        candidateCredentialIdentity: Data,
        previous: RemotePairingRollbackState
    ) {
        self.init(
            transactionID: transactionID,
            candidate: candidate,
            candidateCredentialVerifier: candidateCredentialIdentity,
            previous: previous
        )
    }
}
