import Dependencies
import DependenciesMacros
import Darwin
import Foundation
import RemoteCore

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

struct PreparedPairingPersistenceRecord: Codable, Equatable, Sendable {
    let transactionID: UUID
    let candidate: PairedMac
    let candidateCredentialIdentity: Data
    let previous: RemotePairingRollbackState
}

@DependencyClient
struct RemotePersistenceClient: Sendable {
    var saveAppState: @Sendable (RemoteAppPersistenceIntent) async throws -> Void = { _ in
        throw RemoteDependencyError.unimplemented
    }
    var loadInitialSetupCompleted: @Sendable () async throws -> Bool = { false }
    var saveInitialSetupCompleted: @Sendable (Bool) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var loadPairedMacs: @Sendable () async throws -> [PairedMac] = { [] }
    var savePairedMacs: @Sendable ([PairedMac]) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var upsertPairedMac: @Sendable (PairedMac) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var updateRequiresPairing: @Sendable (UUID, Bool) async throws -> Void = { _, _ in throw RemoteDependencyError.unimplemented }
    var updateEndpoint: @Sendable (UUID, String?, Date?) async throws -> Void = { _, _, _ in throw RemoteDependencyError.unimplemented }
    var removePairedMac: @Sendable (UUID) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var loadSelectedMacID: @Sendable () async throws -> UUID? = { nil }
    var saveSelectedMacID: @Sendable (UUID?) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var loadLayout: @Sendable (UUID) async throws -> MacDashboardLayout? = { _ in nil }
    var saveLayout: @Sendable (MacDashboardLayout) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var loadCatalog: @Sendable (UUID) async throws -> RemoteCatalogCache? = { _ in nil }
    var saveCatalog: @Sendable (UUID, UInt64, [RemoteControlDescriptor]) async throws -> Void = { _, _, _ in throw RemoteDependencyError.unimplemented }
    var loadStatuses: @Sendable (UUID) async throws -> [RemoteControlStatus]? = { _ in nil }
    var saveStatuses: @Sendable (UUID, [RemoteControlStatus]) async throws -> Void = { _, _ in throw RemoteDependencyError.unimplemented }
    var replaceStatusSnapshot: @Sendable (UUID, [RemoteControlStatus]) async throws -> Void = { _, _ in throw RemoteDependencyError.unimplemented }
    var mergeStatus: @Sendable (UUID, RemoteControlStatus) async throws -> Void = { _, _ in throw RemoteDependencyError.unimplemented }
    var markMacTombstoned: @Sendable (UUID) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var preparePairingState: @Sendable (PairedMac, UUID, Data) async throws -> PreparedPairingPersistenceRecord = { _, _, _ in
        throw RemoteDependencyError.unimplemented
    }
    var finalizePairingState: @Sendable (UUID) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var restorePairingState: @Sendable (PreparedPairingPersistenceRecord) async throws -> Void = { _ in
        throw RemoteDependencyError.unimplemented
    }
    var commitPairing: @Sendable (PairedMac) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var commitPairingAndSelect: @Sendable (PairedMac) async throws -> RemotePairingPersistenceSnapshot = { _ in
        throw RemoteDependencyError.unimplemented
    }
    var restorePairingSnapshot: @Sendable (UUID, RemotePairingPersistenceSnapshot) async throws -> Void = { _, _ in
        throw RemoteDependencyError.unimplemented
    }
    var isMacTombstoned: @Sendable (UUID) async -> Bool = { _ in false }
    var forgetMac: @Sendable (UUID) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
}

enum RemoteDependencyError: Swift.Error, Sendable { case unimplemented }

extension RemotePersistenceClient {
    static func inMemory(
        beforeAppStateCommit: @escaping @Sendable (RemoteAppPersistenceIntent) throws -> Void = { _ in }
    ) -> Self {
        let store = InMemoryRemotePersistenceStore(beforeAppStateCommit: beforeAppStateCommit)
        return Self(
            saveAppState: { try await store.saveAppState($0) },
            loadInitialSetupCompleted: { await store.initialSetupCompleted },
            saveInitialSetupCompleted: { await store.setInitialSetupCompleted($0) },
            loadPairedMacs: { await store.pairedMacs },
            savePairedMacs: { await store.setPairedMacs($0) },
            upsertPairedMac: { await store.upsert($0) },
            updateRequiresPairing: { await store.updateRequiresPairing($0, value: $1) },
            updateEndpoint: { await store.updateEndpoint($0, description: $1, connectedAt: $2) },
            removePairedMac: { await store.removePairedMac($0) },
            loadSelectedMacID: { await store.selectedMacID },
            saveSelectedMacID: { await store.setSelectedMacID($0) },
            loadLayout: { await store.loadLayout($0) },
            saveLayout: { await store.setLayout($0) },
            loadCatalog: { await store.loadCatalog($0) },
            saveCatalog: { await store.setCatalog(.init(revision: $1, controls: $2), for: $0) },
            loadStatuses: { await store.loadStatuses($0) },
            saveStatuses: { await store.mergeSnapshot($1, for: $0) },
            replaceStatusSnapshot: { await store.setStatuses($1, for: $0) },
            mergeStatus: { await store.mergeStatus($1, for: $0) },
            markMacTombstoned: { await store.markTombstoned($0) },
            preparePairingState: { try await store.preparePairingState($0, transactionID: $1, credentialIdentity: $2) },
            finalizePairingState: { try await store.finalizePairingState($0) },
            restorePairingState: { try await store.restorePairingState($0) },
            commitPairing: { await store.commitPairing($0) },
            commitPairingAndSelect: { await store.commitPairingAndSelect($0) },
            restorePairingSnapshot: { await store.restorePairingSnapshot(macID: $0, snapshot: $1) },
            isMacTombstoned: { await store.tombstones.contains($0) },
            forgetMac: { await store.forget($0) }
        )
    }

    static var live: Self {
        fileBacked(store: RemotePersistenceLiveContainer.store, keychain: .live)
    }

    static func fileBacked(
        store: RemoteFilePersistenceStore,
        keychain: RemoteKeychainClient
    ) -> Self {
        return Self(
            saveAppState: { try await store.saveAppState($0) },
            loadInitialSetupCompleted: { try await store.loadInitialSetupCompleted() },
            saveInitialSetupCompleted: { try await store.saveInitialSetupCompleted($0) },
            loadPairedMacs: { try await store.loadPairedMacs() },
            savePairedMacs: { try await store.savePairedMacs($0) },
            upsertPairedMac: { try await store.upsertPairedMac($0) },
            updateRequiresPairing: { try await store.updateRequiresPairing($0, value: $1) },
            updateEndpoint: { try await store.updateEndpoint($0, description: $1, connectedAt: $2) },
            removePairedMac: { try await store.removePreferences($0) },
            loadSelectedMacID: { try await store.loadSelectedMacID() },
            saveSelectedMacID: { try await store.saveSelectedMacID($0) },
            loadLayout: { try await store.load(MacDashboardLayout.self, macID: $0, name: "layout.json") },
            saveLayout: { try await store.save($0, macID: $0.macID, name: "layout.json") },
            loadCatalog: { try await store.load(RemoteCatalogCache.self, macID: $0, name: "catalog.json") },
            saveCatalog: { try await store.save(RemoteCatalogCache(revision: $1, controls: $2), macID: $0, name: "catalog.json") },
            loadStatuses: { try await store.load([RemoteControlStatus].self, macID: $0, name: "statuses.json") },
            saveStatuses: { try await store.mergeStatusSnapshot($1, macID: $0) },
            replaceStatusSnapshot: { try await store.save($1, macID: $0, name: "statuses.json") },
            mergeStatus: { try await store.mergeStatus($1, macID: $0) },
            markMacTombstoned: { try await store.markTombstoned($0) },
            preparePairingState: { try await store.preparePairingState($0, transactionID: $1, credentialIdentity: $2) },
            finalizePairingState: { try await store.finalizePairingState($0) },
            restorePairingState: { try await store.restorePairingState($0) },
            commitPairing: { try await store.commitPairing($0) },
            commitPairingAndSelect: { try await store.commitPairingAndSelect($0) },
            restorePairingSnapshot: { try await store.restorePairingSnapshot(macID: $0, snapshot: $1) },
            isMacTombstoned: { (try? await store.isTombstoned($0)) ?? true },
            forgetMac: { id in
                try await store.markTombstoned(id)
                try await keychain.deleteCredential(id)
                try await store.removeCaches(id)
                try await store.removePreferences(id)
            }
        )
    }
}

extension RemotePersistenceClient: DependencyKey {
    static var liveValue: Self { .live }
    static var testValue: Self { Self() }
}

extension DependencyValues {
    var remotePersistence: RemotePersistenceClient {
        get { self[RemotePersistenceClient.self] }
        set { self[RemotePersistenceClient.self] = newValue }
    }
}

extension RemotePersistenceClient {
    static let initialSetupCompletedKey = "hasCompletedInitialSetup"

    static func initialSetupSeed(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: initialSetupCompletedKey)
    }
}

private actor InMemoryRemotePersistenceStore {
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
    var catalogs: [UUID: RemoteCatalogCache] = [:]
    var statuses: [UUID: [RemoteControlStatus]] = [:]
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
    func forget(_ id: UUID) {
        envelope.tombstonedMacIDs.insert(id)
        envelope.pairedMacs.removeAll { $0.id == id }
        if envelope.selectedMacID == id { envelope.selectedMacID = nil }
        layouts[id] = nil
        catalogs[id] = nil
        statuses[id] = nil
    }

    func markTombstoned(_ id: UUID) { envelope.tombstonedMacIDs.insert(id) }

    func preparePairingState(
        _ candidate: PairedMac,
        transactionID: UUID,
        credentialIdentity: Data
    ) throws -> PreparedPairingPersistenceRecord {
        if let prepared = envelope.preparedPairing {
            guard prepared.transactionID == transactionID,
                  prepared.candidate == candidate,
                  prepared.candidateCredentialIdentity == credentialIdentity
            else { throw RemotePersistenceError.pairingAlreadyPrepared }
            return prepared
        }
        let record = PreparedPairingPersistenceRecord(
            transactionID: transactionID,
            candidate: candidate,
            candidateCredentialIdentity: credentialIdentity,
            previous: rollbackState
        )
        envelope.tombstonedMacIDs.remove(candidate.id)
        envelope.pairedMacs.removeAll { $0.id == candidate.id }
        envelope.pairedMacs.append(candidate)
        envelope.selectedMacID = candidate.id
        envelope.preparedPairing = record
        return record
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

private enum RemotePersistenceError: Swift.Error {
    case unsupportedEnvelopeVersion(Int)
    case missingMigratedEnvelope
    case pairingAlreadyPrepared
    case transactionMismatch
}

private func restorePreparedPairing(
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

private enum RemotePersistenceLiveContainer {
    static let store = RemoteFilePersistenceStore()
}

actor RemoteFilePersistenceStore {
    private enum Key {
        static let pairedMacs = "pairedMacs"
        static let selectedMacID = "selectedMacID"
        static let initialSetupCompleted = RemotePersistenceClient.initialSetupCompletedKey
        static let tombstonedMacIDs = "tombstonedMacIDs"
        static let migratedEnvelopeVersion = "remoteStateEnvelopeMigrationVersion"
    }

    private let defaults: UserDefaults
    private let rootURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let removeDirectory: @Sendable (URL) throws -> Void
    private let replaceEnvelope: @Sendable (URL, URL) throws -> Void
    private let synchronizeEnvelopeDirectory: @Sendable (URL) throws -> Void
    private var appStateSequenceTracker = RemoteAppPersistenceSequenceTracker()

    init(
        defaultsSuiteName: String? = nil,
        rootURL: URL? = nil,
        removeDirectory: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        replaceEnvelope: @escaping @Sendable (URL, URL) throws -> Void = RemoteFilePersistenceStore.replaceEnvelopeAtomically,
        synchronizeEnvelopeDirectory: @escaping @Sendable (URL) throws -> Void = RemoteFilePersistenceStore.synchronizeDirectory
    ) {
        self.defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.rootURL = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OnlySwitchRemote", isDirectory: true)
        self.removeDirectory = removeDirectory
        self.replaceEnvelope = replaceEnvelope
        self.synchronizeEnvelopeDirectory = synchronizeEnvelopeDirectory
        encoder.outputFormatting = [.sortedKeys]
    }

    init(
        defaults: UserDefaults,
        rootURL: URL,
        removeDirectory: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        replaceEnvelope: @escaping @Sendable (URL, URL) throws -> Void = RemoteFilePersistenceStore.replaceEnvelopeAtomically,
        synchronizeEnvelopeDirectory: @escaping @Sendable (URL) throws -> Void = RemoteFilePersistenceStore.synchronizeDirectory
    ) {
        self.defaults = defaults
        self.rootURL = rootURL
        self.removeDirectory = removeDirectory
        self.replaceEnvelope = replaceEnvelope
        self.synchronizeEnvelopeDirectory = synchronizeEnvelopeDirectory
        encoder.outputFormatting = [.sortedKeys]
    }

    func loadPairedMacs() throws -> [PairedMac] {
        try loadEnvelope().pairedMacs
    }

    func savePairedMacs(_ macs: [PairedMac]) throws {
        try mutateEnvelope { envelope in
            envelope.pairedMacs = macs.filter { envelope.tombstonedMacIDs.contains($0.id) == false }
        }
    }

    func upsertPairedMac(_ mac: PairedMac) throws {
        try mutateEnvelope {
            guard $0.tombstonedMacIDs.contains(mac.id) == false else { return }
            $0.pairedMacs.removeAll { $0.id == mac.id }
            $0.pairedMacs.append(mac)
        }
    }

    func updateRequiresPairing(_ id: UUID, value: Bool) throws {
        try mutateEnvelope {
            guard $0.tombstonedMacIDs.contains(id) == false else { return }
            guard let index = $0.pairedMacs.firstIndex(where: { $0.id == id }) else { return }
            $0.pairedMacs[index].requiresPairing = value
        }
    }

    func updateEndpoint(_ id: UUID, description: String?, connectedAt: Date?) throws {
        try mutateEnvelope {
            guard $0.tombstonedMacIDs.contains(id) == false else { return }
            guard let index = $0.pairedMacs.firstIndex(where: { $0.id == id }) else { return }
            $0.pairedMacs[index].lastEndpointDescription = description
            $0.pairedMacs[index].lastConnectedAt = connectedAt
        }
    }

    func loadSelectedMacID() throws -> UUID? {
        try loadEnvelope().selectedMacID
    }

    func saveAppState(_ intent: RemoteAppPersistenceIntent) throws {
        guard appStateSequenceTracker.accepts(intent) else { return }
        try mutateEnvelope {
            $0.selectedMacID = intent.selectedMacID
            $0.hasCompletedInitialSetup = intent.hasCompletedInitialSetup
        }
    }

    func loadInitialSetupCompleted() throws -> Bool {
        try loadEnvelope().hasCompletedInitialSetup
    }

    func saveInitialSetupCompleted(_ value: Bool) throws {
        try mutateEnvelope { $0.hasCompletedInitialSetup = value }
    }

    func saveSelectedMacID(_ id: UUID?) throws {
        try mutateEnvelope { $0.selectedMacID = id }
    }

    func load<Value: Decodable>(_ type: Value.Type, macID: UUID, name: String) throws -> Value? {
        guard try loadEnvelope().tombstonedMacIDs.contains(macID) == false else { return nil }
        let url = directory(for: macID).appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(type, from: Data(contentsOf: url, options: .mappedIfSafe))
    }

    func save<Value: Encodable>(_ value: Value, macID: UUID, name: String) throws {
        guard try loadEnvelope().tombstonedMacIDs.contains(macID) == false else { return }
        let directory = directory(for: macID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(value).write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func mergeStatus(_ status: RemoteControlStatus, macID: UUID) throws {
        guard try loadEnvelope().tombstonedMacIDs.contains(macID) == false else { return }
        var values = try load([RemoteControlStatus].self, macID: macID, name: "statuses.json") ?? []
        if let existing = values.first(where: { $0.id == status.id }), existing.revision > status.revision {
            return
        }
        values.removeAll { $0.id == status.id }
        values.append(status)
        try save(values, macID: macID, name: "statuses.json")
    }

    func mergeStatusSnapshot(_ incoming: [RemoteControlStatus], macID: UUID) throws {
        guard try loadEnvelope().tombstonedMacIDs.contains(macID) == false else { return }
        let cached = try load([RemoteControlStatus].self, macID: macID, name: "statuses.json") ?? []
        let existing = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        let merged = incoming.map { value in
            guard let current = existing[value.id], current.revision > value.revision else { return value }
            return current
        }
        try save(merged, macID: macID, name: "statuses.json")
    }

    func removePreferences(_ id: UUID) throws {
        try mutateEnvelope {
            $0.pairedMacs.removeAll { $0.id == id }
            if $0.selectedMacID == id { $0.selectedMacID = nil }
        }
    }

    func removeCaches(_ id: UUID) throws {
        let directory = directory(for: id)
        if FileManager.default.fileExists(atPath: directory.path) {
            try removeDirectory(directory)
        }
    }

    func markTombstoned(_ id: UUID) throws {
        try mutateEnvelope { $0.tombstonedMacIDs.insert(id) }
    }

    func isTombstoned(_ id: UUID) throws -> Bool {
        try loadEnvelope().tombstonedMacIDs.contains(id)
    }

    func commitPairing(_ mac: PairedMac) throws {
        try mutateEnvelope {
            $0.tombstonedMacIDs.remove(mac.id)
            $0.pairedMacs.removeAll { $0.id == mac.id }
            $0.pairedMacs.append(mac)
        }
    }

    func preparePairingState(
        _ candidate: PairedMac,
        transactionID: UUID,
        credentialIdentity: Data
    ) throws -> PreparedPairingPersistenceRecord {
        try mutateEnvelope { envelope in
            if let prepared = envelope.preparedPairing {
                guard prepared.transactionID == transactionID,
                      prepared.candidate == candidate,
                      prepared.candidateCredentialIdentity == credentialIdentity
                else { throw RemotePersistenceError.pairingAlreadyPrepared }
                return prepared
            }
            let record = PreparedPairingPersistenceRecord(
                transactionID: transactionID,
                candidate: candidate,
                candidateCredentialIdentity: credentialIdentity,
                previous: rollbackState(for: envelope)
            )
            envelope.tombstonedMacIDs.remove(candidate.id)
            envelope.pairedMacs.removeAll { $0.id == candidate.id }
            envelope.pairedMacs.append(candidate)
            envelope.selectedMacID = candidate.id
            envelope.preparedPairing = record
            return record
        }
    }

    func finalizePairingState(_ transactionID: UUID) throws {
        try mutateEnvelope {
            guard let prepared = $0.preparedPairing else { return }
            guard prepared.transactionID == transactionID else { throw RemotePersistenceError.transactionMismatch }
            $0.preparedPairing = nil
        }
    }

    func restorePairingState(_ record: PreparedPairingPersistenceRecord) throws {
        try mutateEnvelope { try restorePreparedPairing(record, in: &$0) }
    }

    func commitPairingAndSelect(_ mac: PairedMac) throws -> RemotePairingPersistenceSnapshot {
        try mutateEnvelope {
            let snapshot = RemotePairingPersistenceSnapshot(
                previousMac: $0.pairedMacs.first { $0.id == mac.id },
                previousSelectedMacID: $0.selectedMacID,
                wasTombstoned: $0.tombstonedMacIDs.contains(mac.id)
            )
            $0.tombstonedMacIDs.remove(mac.id)
            $0.pairedMacs.removeAll { $0.id == mac.id }
            $0.pairedMacs.append(mac)
            $0.selectedMacID = mac.id
            return snapshot
        }
    }

    func restorePairingSnapshot(
        macID: UUID,
        snapshot: RemotePairingPersistenceSnapshot
    ) throws {
        try mutateEnvelope {
            $0.pairedMacs.removeAll { $0.id == macID }
            if snapshot.wasTombstoned {
                $0.tombstonedMacIDs.insert(macID)
            } else {
                $0.tombstonedMacIDs.remove(macID)
                if let previousMac = snapshot.previousMac { $0.pairedMacs.append(previousMac) }
            }
            $0.selectedMacID = snapshot.previousSelectedMacID
        }
    }

    func loadEnvelope() throws -> RemotePersistentStateEnvelope {
        let url = envelopeURL
        if FileManager.default.fileExists(atPath: url.path) {
            let envelope = try decoder.decode(
                RemotePersistentStateEnvelope.self,
                from: Data(contentsOf: url, options: .mappedIfSafe)
            )
            guard envelope.version == 1 else {
                throw RemotePersistenceError.unsupportedEnvelopeVersion(envelope.version)
            }
            if defaults.integer(forKey: Key.migratedEnvelopeVersion) < 1 {
                try synchronizeEnvelopeDirectory(rootURL)
                defaults.set(1, forKey: Key.migratedEnvelopeVersion)
            }
            return envelope
        }

        guard defaults.integer(forKey: Key.migratedEnvelopeVersion) < 1 else {
            throw RemotePersistenceError.missingMigratedEnvelope
        }

        let legacyMacs: [PairedMac]
        if let data = defaults.data(forKey: Key.pairedMacs) {
            legacyMacs = try decoder.decode([PairedMac].self, from: data)
        } else {
            legacyMacs = []
        }
        let legacyTombstones: Set<UUID>
        if let data = defaults.data(forKey: Key.tombstonedMacIDs) {
            legacyTombstones = try decoder.decode(Set<UUID>.self, from: data)
        } else {
            legacyTombstones = []
        }
        let migrated = RemotePersistentStateEnvelope(
            pairedMacs: legacyMacs,
            selectedMacID: defaults.string(forKey: Key.selectedMacID).flatMap(UUID.init(uuidString:)),
            hasCompletedInitialSetup: defaults.bool(forKey: Key.initialSetupCompleted),
            tombstonedMacIDs: legacyTombstones
        )
        try saveEnvelope(migrated)
        defaults.set(1, forKey: Key.migratedEnvelopeVersion)
        return migrated
    }

    func saveEnvelope(_ envelope: RemotePersistentStateEnvelope) throws {
        guard envelope.version == 1 else {
            throw RemotePersistenceError.unsupportedEnvelopeVersion(envelope.version)
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let temporaryURL = rootURL.appendingPathComponent(".state-envelope-v1-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporaryURL)
        do {
            try handle.write(contentsOf: encoder.encode(envelope))
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        try replaceEnvelope(temporaryURL, envelopeURL)
        defaults.set(envelope.hasCompletedInitialSetup, forKey: Key.initialSetupCompleted)
        try synchronizeEnvelopeDirectory(rootURL)
    }

    private func mutateEnvelope<Result>(
        _ mutation: (inout RemotePersistentStateEnvelope) throws -> Result
    ) throws -> Result {
        var envelope = try loadEnvelope()
        let original = envelope
        let result = try mutation(&envelope)
        if envelope != original {
            try saveEnvelope(envelope)
        }
        return result
    }

    private func rollbackState(for envelope: RemotePersistentStateEnvelope) -> RemotePairingRollbackState {
        RemotePairingRollbackState(
            pairedMacs: envelope.pairedMacs,
            selectedMacID: envelope.selectedMacID,
            hasCompletedInitialSetup: envelope.hasCompletedInitialSetup,
            tombstonedMacIDs: envelope.tombstonedMacIDs
        )
    }

    private var envelopeURL: URL {
        rootURL.appendingPathComponent("state-envelope-v1.json")
    }

    private nonisolated static func replaceEnvelopeAtomically(_ temporaryURL: URL, _ envelopeURL: URL) throws {
        guard rename(temporaryURL.path, envelopeURL.path) == 0 else {
            throw currentPOSIXError()
        }
    }

    private nonisolated static func synchronizeDirectory(_ directoryURL: URL) throws {
        let descriptor = open(directoryURL.path, O_RDONLY)
        guard descriptor >= 0 else { throw currentPOSIXError() }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw currentPOSIXError() }
    }

    private nonisolated static func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private func directory(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }
}

private struct RemoteAppPersistenceSequenceTracker {
    private static let writerLimit = 8
    private var highestSequenceByWriter: [UUID: UInt64] = [:]
    private var writerInsertionOrder: [UUID] = []

    mutating func accepts(_ intent: RemoteAppPersistenceIntent) -> Bool {
        if let highest = highestSequenceByWriter[intent.writerID] {
            guard intent.sequence >= highest else { return false }
            highestSequenceByWriter[intent.writerID] = intent.sequence
            return true
        }

        highestSequenceByWriter[intent.writerID] = intent.sequence
        writerInsertionOrder.append(intent.writerID)
        if writerInsertionOrder.count > Self.writerLimit {
            let removed = writerInsertionOrder.removeFirst()
            highestSequenceByWriter[removed] = nil
        }
        return true
    }
}
