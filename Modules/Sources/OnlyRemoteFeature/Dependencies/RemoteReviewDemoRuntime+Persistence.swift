import Foundation
import Network
import RemoteCore

extension RemoteReviewDemoRuntime {
    func appState() -> (Bool, [PairedMac], UUID?) {
        (hasCompletedInitialSetup, pairedMacs, selectedMacID)
    }

    func saveAppState(_ intent: RemoteAppPersistenceIntent) {
        selectedMacID = intent.selectedMacID
        hasCompletedInitialSetup = intent.hasCompletedInitialSetup
    }

    func setInitialSetupCompleted(_ value: Bool) { hasCompletedInitialSetup = value }
    func setPairedMacs(_ value: [PairedMac]) { pairedMacs = value.filter { tombstones.contains($0.id) == false } }
    func upsert(_ mac: PairedMac) {
        guard tombstones.contains(mac.id) == false else { return }
        pairedMacs.removeAll { $0.id == mac.id }
        pairedMacs.append(mac)
    }
    func updateRequiresPairing(_ id: UUID, value: Bool) {
        guard let index = pairedMacs.firstIndex(where: { $0.id == id }) else { return }
        pairedMacs[index].requiresPairing = value
    }
    func updateEndpoint(_ id: UUID, description: String?, connectedAt: Date?) {
        guard let index = pairedMacs.firstIndex(where: { $0.id == id }) else { return }
        pairedMacs[index].lastEndpointDescription = description
        pairedMacs[index].lastConnectedAt = connectedAt
    }
    func removePairedMac(_ id: UUID) {
        pairedMacs.removeAll { $0.id == id }
        if selectedMacID == id { selectedMacID = pairedMacs.first?.id }
    }
    func setSelectedMacID(_ id: UUID?) { selectedMacID = id }
    func layout(for id: UUID) -> MacDashboardLayout? { tombstones.contains(id) ? nil : layouts[id] }
    func setLayout(_ layout: MacDashboardLayout) { if tombstones.contains(layout.macID) == false { layouts[layout.macID] = layout } }
    func systemMonitorLayout(for id: UUID) -> MacSystemMonitorLayout? {
        tombstones.contains(id) ? nil : systemMonitorLayouts[id]
    }
    func setSystemMonitorLayout(_ layout: MacSystemMonitorLayout) {
        if tombstones.contains(layout.macID) == false { systemMonitorLayouts[layout.macID] = layout }
    }
    func catalog(for id: UUID) -> RemoteCatalogCache? { tombstones.contains(id) ? nil : catalogs[id] }
    func setCatalog(_ catalog: RemoteCatalogCache, for id: UUID) { if tombstones.contains(id) == false { catalogs[id] = catalog } }
    func statuses(for id: UUID) -> [RemoteControlStatus]? { tombstones.contains(id) ? nil : statuses[id] }
    func setStatuses(_ value: [RemoteControlStatus], for id: UUID) { if tombstones.contains(id) == false { statuses[id] = value } }
    func mergeStatus(_ status: RemoteControlStatus, for id: UUID) {
        guard tombstones.contains(id) == false else { return }
        var values = statuses[id] ?? []
        values.removeAll { $0.id == status.id }
        values.append(status)
        statuses[id] = values
    }
    func markTombstoned(_ id: UUID) { tombstones.insert(id) }
    func isTombstoned(_ id: UUID) -> Bool { tombstones.contains(id) }
    func forget(_ id: UUID) {
        tombstones.insert(id)
        removePairedMac(id)
        layouts[id] = nil
        systemMonitorLayouts[id] = nil
        catalogs[id] = nil
        statuses[id] = nil
    }

    func preparePairingState(
        _ mac: PairedMac,
        transactionID: UUID,
        credentialVerifier: Data
    ) -> PreparedPairingPersistenceRecord {
        let previous = RemotePairingRollbackState(
            pairedMacs: pairedMacs,
            selectedMacID: selectedMacID,
            hasCompletedInitialSetup: hasCompletedInitialSetup,
            tombstonedMacIDs: tombstones
        )
        let record = PreparedPairingPersistenceRecord(
            transactionID: transactionID,
            candidate: mac,
            candidateCredentialVerifier: credentialVerifier,
            previous: previous
        )
        preparedPairingRecord = record
        return record
    }

    func loadPreparedPairingState() -> PreparedPairingPersistenceRecord? { preparedPairingRecord }
    func adoptPreparedPairingState(_ transactionID: UUID) throws {
        guard var record = preparedPairingRecord, record.transactionID == transactionID else { throw RemoteDependencyError.unimplemented }
        record.phase = .adopted
        preparedPairingRecord = record
        upsert(record.candidate)
        selectedMacID = record.candidate.id
    }
    func finalizePairingState(_ transactionID: UUID) throws {
        guard preparedPairingRecord?.transactionID == transactionID else { throw RemoteDependencyError.unimplemented }
        preparedPairingRecord = nil
    }
    func restorePairingState(_ record: PreparedPairingPersistenceRecord) {
        pairedMacs = record.previous.pairedMacs
        selectedMacID = record.previous.selectedMacID
        hasCompletedInitialSetup = record.previous.hasCompletedInitialSetup
        tombstones = record.previous.tombstonedMacIDs
        preparedPairingRecord = nil
    }
    func commitPairingAndSelect(_ mac: PairedMac) -> RemotePairingPersistenceSnapshot {
        let snapshot = RemotePairingPersistenceSnapshot(
            previousMac: pairedMacs.first(where: { $0.id == mac.id }),
            previousSelectedMacID: selectedMacID,
            wasTombstoned: tombstones.contains(mac.id)
        )
        tombstones.remove(mac.id)
        upsert(mac)
        selectedMacID = mac.id
        hasCompletedInitialSetup = true
        return snapshot
    }
    func restorePairingSnapshot(macID: UUID, snapshot: RemotePairingPersistenceSnapshot) {
        pairedMacs.removeAll { $0.id == macID }
        if let previousMac = snapshot.previousMac { pairedMacs.append(previousMac) }
        selectedMacID = snapshot.previousSelectedMacID
        if snapshot.wasTombstoned { tombstones.insert(macID) } else { tombstones.remove(macID) }
    }

    var canonicalDiscoveredMacs: [DiscoveredMac] {
        [
            .init(id: Self.studioMacID, displayName: "Studio", endpoint: .hostPort(host: "studio.local", port: 41_210), protocolVersion: .current),
            .init(id: Self.travelMacID, displayName: "Travel", endpoint: .hostPort(host: "travel.local", port: 41_211), protocolVersion: .current),
        ]
    }
}
