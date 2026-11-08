import Foundation
import RemoteCore

actor InMemoryRemotePersistenceStore {
    private var appStateSequenceTracker = RemoteAppPersistenceSequenceTracker()
    private let beforeAppStateCommit: @Sendable (RemoteAppPersistenceIntent) throws -> Void
    private var envelope = RemotePersistentStateEnvelope(
        pairedMacs: [],
        selectedMacID: nil,
        hasCompletedInitialSetup: false
    )
    var initialSetupCompleted: Bool { envelope.hasCompletedInitialSetup }
    var pairedMacs: [PairedMac] { envelope.pairedMacs }
    var selectedMacID: UUID? { envelope.selectedMacID }
    var layouts: [UUID: MacDashboardLayout] = [:]
    var systemMonitorLayouts: [UUID: MacSystemMonitorLayout] = [:]
    var catalogs: [UUID: RemoteCatalogCache] = [:]
    var statuses: [UUID: [RemoteControlStatus]] = [:]
    var aphroditeLibraries: [UUID: AphroditeRemoteLibrarySnapshot] = [:]
    var tombstones: Set<UUID> { envelope.tombstonedMacIDs }

    init(beforeAppStateCommit: @escaping @Sendable (RemoteAppPersistenceIntent) throws -> Void) {
        self.beforeAppStateCommit = beforeAppStateCommit
    }

    func saveAppState(_ intent: RemoteAppPersistenceIntent) throws {
        guard appStateSequenceTracker.accepts(intent) else { return }
        try beforeAppStateCommit(intent)
        envelope.selectedMacID = intent.selectedMacID
        envelope.hasCompletedInitialSetup = intent.hasCompletedInitialSetup
    }

    func setInitialSetupCompleted(_ value: Bool) { envelope.hasCompletedInitialSetup = value }

    func setPairedMacs(_ value: [PairedMac]) {
        envelope.pairedMacs = value.filter { envelope.tombstonedMacIDs.contains($0.id) == false }
    }
    func upsert(_ value: PairedMac) {
        guard envelope.tombstonedMacIDs.contains(value.id) == false else { return }
        envelope.pairedMacs.removeAll { $0.id == value.id }
        envelope.pairedMacs.append(value)
    }
    func updateRequiresPairing(_ id: UUID, value: Bool) {
        guard envelope.tombstonedMacIDs.contains(id) == false else { return }
        guard let index = envelope.pairedMacs.firstIndex(where: { $0.id == id }) else { return }
        envelope.pairedMacs[index].requiresPairing = value
    }
    func updateEndpoint(_ id: UUID, description: String?, connectedAt: Date?) {
        guard envelope.tombstonedMacIDs.contains(id) == false else { return }
        guard let index = envelope.pairedMacs.firstIndex(where: { $0.id == id }) else { return }
        envelope.pairedMacs[index].lastEndpointDescription = description
        envelope.pairedMacs[index].lastConnectedAt = connectedAt
    }
    func removePairedMac(_ id: UUID) {
        envelope.pairedMacs.removeAll { $0.id == id }
        if envelope.selectedMacID == id { envelope.selectedMacID = nil }
    }
    func setSelectedMacID(_ value: UUID?) { envelope.selectedMacID = value }
    func setLayout(_ value: MacDashboardLayout) {
        guard tombstones.contains(value.macID) == false else { return }
        layouts[value.macID] = value
    }
    func loadLayout(_ id: UUID) -> MacDashboardLayout? { tombstones.contains(id) ? nil : layouts[id] }
    func setSystemMonitorLayout(_ value: MacSystemMonitorLayout) {
        guard tombstones.contains(value.macID) == false else { return }
        systemMonitorLayouts[value.macID] = value
    }
    func loadSystemMonitorLayout(_ id: UUID) -> MacSystemMonitorLayout? {
        tombstones.contains(id) ? nil : systemMonitorLayouts[id]
    }
    func loadCatalog(_ id: UUID) -> RemoteCatalogCache? { tombstones.contains(id) ? nil : catalogs[id] }
    func loadStatuses(_ id: UUID) -> [RemoteControlStatus]? { tombstones.contains(id) ? nil : statuses[id] }
    func setCatalog(_ value: RemoteCatalogCache, for id: UUID) {
        guard tombstones.contains(id) == false else { return }
        catalogs[id] = value
    }
    func setStatuses(_ value: [RemoteControlStatus], for id: UUID) {
        guard tombstones.contains(id) == false else { return }
        statuses[id] = value
    }
    func mergeSnapshot(_ incoming: [RemoteControlStatus], for id: UUID) {
        guard tombstones.contains(id) == false else { return }
        let existing = Dictionary(uniqueKeysWithValues: (statuses[id] ?? []).map { ($0.id, $0) })
        statuses[id] = incoming.map { value in
            guard let cached = existing[value.id], cached.revision > value.revision else { return value }
            return cached
        }
    }
    func mergeStatus(_ value: RemoteControlStatus, for id: UUID) {
        guard tombstones.contains(id) == false else { return }
        var values = statuses[id] ?? []
        if let existing = values.first(where: { $0.id == value.id }), existing.revision > value.revision {
            return
        }
        values.removeAll { $0.id == value.id }
        values.append(value)
        statuses[id] = values
    }
    func loadAphroditeLibrary(_ id: UUID) -> AphroditeRemoteLibrarySnapshot? {
        tombstones.contains(id) ? nil : aphroditeLibraries[id]
    }
    func replaceAphroditeLibrary(_ value: AphroditeRemoteLibrarySnapshot, for id: UUID) throws {
        guard tombstones.contains(id) == false else { return }
        let value = try value.validated()
        if let current = aphroditeLibraries[id], current.revision >= value.revision { return }
        aphroditeLibraries[id] = value
    }
    func forget(_ id: UUID) {
        envelope.tombstonedMacIDs.insert(id)
        envelope.pairedMacs.removeAll { $0.id == id }
        if envelope.selectedMacID == id { envelope.selectedMacID = nil }
        layouts[id] = nil
        systemMonitorLayouts[id] = nil
        catalogs[id] = nil
        statuses[id] = nil
        aphroditeLibraries[id] = nil
    }

    func markTombstoned(_ id: UUID) { envelope.tombstonedMacIDs.insert(id) }

    func preparePairingState(
        _ candidate: PairedMac,
        transactionID: UUID,
        credentialVerifier: Data
    ) throws -> PreparedPairingPersistenceRecord {
        if let prepared = envelope.preparedPairing {
            guard prepared.transactionID == transactionID,
                  prepared.candidate == candidate,
                  prepared.candidateCredentialVerifier == credentialVerifier
            else { throw RemotePersistenceError.pairingAlreadyPrepared }
            return prepared
        }
        let record = PreparedPairingPersistenceRecord(
            transactionID: transactionID,
            candidate: candidate,
            candidateCredentialVerifier: credentialVerifier,
            previous: rollbackState
        )
        envelope.tombstonedMacIDs.remove(candidate.id)
        envelope.pairedMacs.removeAll { $0.id == candidate.id }
        envelope.pairedMacs.append(candidate)
        envelope.selectedMacID = candidate.id
        envelope.preparedPairing = record
        return record
    }

    func preparePairingState(
        _ candidate: PairedMac,
        transactionID: UUID,
        credentialIdentity: Data
    ) throws -> PreparedPairingPersistenceRecord {
        try preparePairingState(candidate, transactionID: transactionID, credentialVerifier: credentialIdentity)
    }

    var preparedPairingState: PreparedPairingPersistenceRecord? { envelope.preparedPairing }

    func adoptPreparedPairingState(_ transactionID: UUID) throws {
        guard var prepared = envelope.preparedPairing else { throw RemotePersistenceError.transactionMismatch }
        guard prepared.transactionID == transactionID else { throw RemotePersistenceError.transactionMismatch }
        if prepared.phase == .adopted { return }
        prepared.phase = .adopted
        envelope.preparedPairing = prepared
    }

    func finalizePairingState(_ transactionID: UUID) throws {
        guard let prepared = envelope.preparedPairing else { return }
        guard prepared.transactionID == transactionID else { throw RemotePersistenceError.transactionMismatch }
        envelope.preparedPairing = nil
    }

    func restorePairingState(_ record: PreparedPairingPersistenceRecord) throws {
        try restorePreparedPairing(record, in: &envelope)
    }

    func commitPairing(_ mac: PairedMac) {
        envelope.tombstonedMacIDs.remove(mac.id)
        envelope.pairedMacs.removeAll { $0.id == mac.id }
        envelope.pairedMacs.append(mac)
    }

    func commitPairingAndSelect(_ mac: PairedMac) -> RemotePairingPersistenceSnapshot {
        let snapshot = RemotePairingPersistenceSnapshot(
            previousMac: envelope.pairedMacs.first { $0.id == mac.id },
            previousSelectedMacID: envelope.selectedMacID,
            wasTombstoned: envelope.tombstonedMacIDs.contains(mac.id)
        )
        commitPairing(mac)
        envelope.selectedMacID = mac.id
        return snapshot
    }

    func restorePairingSnapshot(macID: UUID, snapshot: RemotePairingPersistenceSnapshot) {
        envelope.pairedMacs.removeAll { $0.id == macID }
        if snapshot.wasTombstoned {
            envelope.tombstonedMacIDs.insert(macID)
        } else {
            envelope.tombstonedMacIDs.remove(macID)
            if let previousMac = snapshot.previousMac { envelope.pairedMacs.append(previousMac) }
        }
        envelope.selectedMacID = snapshot.previousSelectedMacID
    }

    private var rollbackState: RemotePairingRollbackState {
        RemotePairingRollbackState(
            pairedMacs: envelope.pairedMacs,
            selectedMacID: envelope.selectedMacID,
            hasCompletedInitialSetup: envelope.hasCompletedInitialSetup,
            tombstonedMacIDs: envelope.tombstonedMacIDs
        )
    }
}

enum RemotePersistenceError: Swift.Error {
    case unsupportedEnvelopeVersion(Int)
    case missingMigratedEnvelope
    case pairingAlreadyPrepared
    case transactionMismatch
}

func restorePreparedPairing(
    _ supplied: PreparedPairingPersistenceRecord,
    in envelope: inout RemotePersistentStateEnvelope
) throws {
    guard let persisted = envelope.preparedPairing else { return }
    guard persisted == supplied else { throw RemotePersistenceError.transactionMismatch }

    let candidateID = persisted.candidate.id
    let wasTombstonedBefore = persisted.previous.tombstonedMacIDs.contains(candidateID)
    let wasTombstonedAfterPrepare = envelope.tombstonedMacIDs.contains(candidateID) && !wasTombstonedBefore
    envelope.pairedMacs.removeAll { $0.id == candidateID }

    if wasTombstonedAfterPrepare || wasTombstonedBefore {
        envelope.tombstonedMacIDs.insert(candidateID)
    } else {
        envelope.tombstonedMacIDs.remove(candidateID)
        if let previousCandidate = persisted.previous.pairedMacs.first(where: { $0.id == candidateID }) {
            envelope.pairedMacs.append(previousCandidate)
        }
    }

    if envelope.selectedMacID == candidateID {
        envelope.selectedMacID = persisted.previous.selectedMacID
    }
    envelope.preparedPairing = nil
}
