import Dependencies
import DependenciesMacros
import Foundation
import RemoteCore

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
    var loadSystemMonitorLayout: @Sendable (UUID) async throws -> MacSystemMonitorLayout? = { _ in nil }
    var saveSystemMonitorLayout: @Sendable (MacSystemMonitorLayout) async throws -> Void = { _ in
        throw RemoteDependencyError.unimplemented
    }
    var loadCatalog: @Sendable (UUID) async throws -> RemoteCatalogCache? = { _ in nil }
    var saveCatalog: @Sendable (UUID, UInt64, [RemoteControlDescriptor]) async throws -> Void = { _, _, _ in throw RemoteDependencyError.unimplemented }
    var loadStatuses: @Sendable (UUID) async throws -> [RemoteControlStatus]? = { _ in nil }
    var saveStatuses: @Sendable (UUID, [RemoteControlStatus]) async throws -> Void = { _, _ in throw RemoteDependencyError.unimplemented }
    var replaceStatusSnapshot: @Sendable (UUID, [RemoteControlStatus]) async throws -> Void = { _, _ in throw RemoteDependencyError.unimplemented }
    var mergeStatus: @Sendable (UUID, RemoteControlStatus) async throws -> Void = { _, _ in throw RemoteDependencyError.unimplemented }
    var loadAphroditeLibrary: @Sendable (UUID) async throws -> AphroditeRemoteLibrarySnapshot? = { _ in nil }
    var replaceAphroditeLibrary: @Sendable (UUID, AphroditeRemoteLibrarySnapshot) async throws -> Void = { _, _ in
        throw RemoteDependencyError.unimplemented
    }
    var markMacTombstoned: @Sendable (UUID) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var preparePairingState: @Sendable (PairedMac, UUID, Data) async throws -> PreparedPairingPersistenceRecord = { _, _, _ in
        throw RemoteDependencyError.unimplemented
    }
    var loadPreparedPairingState: @Sendable () async throws -> PreparedPairingPersistenceRecord? = { nil }
    var adoptPreparedPairingState: @Sendable (UUID) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
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
            loadSystemMonitorLayout: { await store.loadSystemMonitorLayout($0) },
            saveSystemMonitorLayout: { await store.setSystemMonitorLayout($0) },
            loadCatalog: { await store.loadCatalog($0) },
            saveCatalog: { await store.setCatalog(.init(revision: $1, controls: $2), for: $0) },
            loadStatuses: { await store.loadStatuses($0) },
            saveStatuses: { await store.mergeSnapshot($1, for: $0) },
            replaceStatusSnapshot: { await store.setStatuses($1, for: $0) },
            mergeStatus: { await store.mergeStatus($1, for: $0) },
            loadAphroditeLibrary: { await store.loadAphroditeLibrary($0) },
            replaceAphroditeLibrary: { try await store.replaceAphroditeLibrary($1, for: $0) },
            markMacTombstoned: { await store.markTombstoned($0) },
            preparePairingState: { try await store.preparePairingState($0, transactionID: $1, credentialVerifier: $2) },
            loadPreparedPairingState: { await store.preparedPairingState },
            adoptPreparedPairingState: { try await store.adoptPreparedPairingState($0) },
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
            loadSystemMonitorLayout: {
                try await store.load(MacSystemMonitorLayout.self, macID: $0, name: "system-monitor-layout.json")
            },
            saveSystemMonitorLayout: {
                try await store.save($0, macID: $0.macID, name: "system-monitor-layout.json")
            },
            loadCatalog: { try await store.load(RemoteCatalogCache.self, macID: $0, name: "catalog.json") },
            saveCatalog: { try await store.save(RemoteCatalogCache(revision: $1, controls: $2), macID: $0, name: "catalog.json") },
            loadStatuses: { try await store.load([RemoteControlStatus].self, macID: $0, name: "statuses.json") },
            saveStatuses: { try await store.mergeStatusSnapshot($1, macID: $0) },
            replaceStatusSnapshot: { try await store.save($1, macID: $0, name: "statuses.json") },
            mergeStatus: { try await store.mergeStatus($1, macID: $0) },
            loadAphroditeLibrary: { try await store.load(AphroditeRemoteLibrarySnapshot.self, macID: $0, name: "aphrodite-library.json") },
            replaceAphroditeLibrary: { macID, snapshot in
                try await store.replaceAphroditeLibrary(snapshot, macID: macID)
            },
            markMacTombstoned: { try await store.markTombstoned($0) },
            preparePairingState: { try await store.preparePairingState($0, transactionID: $1, credentialVerifier: $2) },
            loadPreparedPairingState: { try await store.loadPreparedPairingState() },
            adoptPreparedPairingState: { try await store.adoptPreparedPairingState($0) },
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
