import Dependencies
import DependenciesMacros
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
            loadInitialSetupCompleted: { await store.loadInitialSetupCompleted() },
            saveInitialSetupCompleted: { await store.saveInitialSetupCompleted($0) },
            loadPairedMacs: { try await store.loadPairedMacs() },
            savePairedMacs: { try await store.savePairedMacs($0) },
            upsertPairedMac: { try await store.upsertPairedMac($0) },
            updateRequiresPairing: { try await store.updateRequiresPairing($0, value: $1) },
            updateEndpoint: { try await store.updateEndpoint($0, description: $1, connectedAt: $2) },
            removePairedMac: { try await store.removePreferences($0) },
            loadSelectedMacID: { await store.loadSelectedMacID() },
            saveSelectedMacID: { await store.saveSelectedMacID($0) },
            loadLayout: { try await store.load(MacDashboardLayout.self, macID: $0, name: "layout.json") },
            saveLayout: { try await store.save($0, macID: $0.macID, name: "layout.json") },
            loadCatalog: { try await store.load(RemoteCatalogCache.self, macID: $0, name: "catalog.json") },
            saveCatalog: { try await store.save(RemoteCatalogCache(revision: $1, controls: $2), macID: $0, name: "catalog.json") },
            loadStatuses: { try await store.load([RemoteControlStatus].self, macID: $0, name: "statuses.json") },
            saveStatuses: { try await store.mergeStatusSnapshot($1, macID: $0) },
            replaceStatusSnapshot: { try await store.save($1, macID: $0, name: "statuses.json") },
            mergeStatus: { try await store.mergeStatus($1, macID: $0) },
            markMacTombstoned: { await store.markTombstoned($0) },
            commitPairing: { try await store.commitPairing($0) },
            commitPairingAndSelect: { try await store.commitPairingAndSelect($0) },
            restorePairingSnapshot: { try await store.restorePairingSnapshot(macID: $0, snapshot: $1) },
            isMacTombstoned: { await store.isTombstoned($0) },
            forgetMac: { id in
                await store.markTombstoned(id)
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
    var initialSetupCompleted = false
    var pairedMacs: [PairedMac] = []
    var selectedMacID: UUID?
    var layouts: [UUID: MacDashboardLayout] = [:]
    var catalogs: [UUID: RemoteCatalogCache] = [:]
    var statuses: [UUID: [RemoteControlStatus]] = [:]
    var tombstones: Set<UUID> = []

    init(beforeAppStateCommit: @escaping @Sendable (RemoteAppPersistenceIntent) throws -> Void) {
        self.beforeAppStateCommit = beforeAppStateCommit
    }

    func saveAppState(_ intent: RemoteAppPersistenceIntent) throws {
        guard appStateSequenceTracker.accepts(intent) else { return }
        try beforeAppStateCommit(intent)
        selectedMacID = intent.selectedMacID
        initialSetupCompleted = intent.hasCompletedInitialSetup
    }

    func setInitialSetupCompleted(_ value: Bool) { initialSetupCompleted = value }

    func setPairedMacs(_ value: [PairedMac]) { pairedMacs = value.filter { tombstones.contains($0.id) == false } }
    func upsert(_ value: PairedMac) {
        guard tombstones.contains(value.id) == false else { return }
        pairedMacs.removeAll { $0.id == value.id }
        pairedMacs.append(value)
    }
    func updateRequiresPairing(_ id: UUID, value: Bool) {
        guard tombstones.contains(id) == false else { return }
        guard let index = pairedMacs.firstIndex(where: { $0.id == id }) else { return }
        pairedMacs[index].requiresPairing = value
    }
    func updateEndpoint(_ id: UUID, description: String?, connectedAt: Date?) {
        guard tombstones.contains(id) == false else { return }
        guard let index = pairedMacs.firstIndex(where: { $0.id == id }) else { return }
        pairedMacs[index].lastEndpointDescription = description
        pairedMacs[index].lastConnectedAt = connectedAt
    }
    func removePairedMac(_ id: UUID) {
        pairedMacs.removeAll { $0.id == id }
        if selectedMacID == id { selectedMacID = nil }
    }
    func setSelectedMacID(_ value: UUID?) { selectedMacID = value }
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
        tombstones.insert(id)
        pairedMacs.removeAll { $0.id == id }
        if selectedMacID == id { selectedMacID = nil }
        layouts[id] = nil
        catalogs[id] = nil
        statuses[id] = nil
    }

    func markTombstoned(_ id: UUID) { tombstones.insert(id) }

    func commitPairing(_ mac: PairedMac) {
        tombstones.remove(mac.id)
        pairedMacs.removeAll { $0.id == mac.id }
        pairedMacs.append(mac)
    }

    func commitPairingAndSelect(_ mac: PairedMac) -> RemotePairingPersistenceSnapshot {
        let snapshot = RemotePairingPersistenceSnapshot(
            previousMac: pairedMacs.first { $0.id == mac.id },
            previousSelectedMacID: selectedMacID,
            wasTombstoned: tombstones.contains(mac.id)
        )
        commitPairing(mac)
        selectedMacID = mac.id
        return snapshot
    }

    func restorePairingSnapshot(macID: UUID, snapshot: RemotePairingPersistenceSnapshot) {
        pairedMacs.removeAll { $0.id == macID }
        if snapshot.wasTombstoned {
            tombstones.insert(macID)
        } else {
            tombstones.remove(macID)
            if let previousMac = snapshot.previousMac { pairedMacs.append(previousMac) }
        }
        selectedMacID = snapshot.previousSelectedMacID
    }
}

private enum RemotePersistenceLiveContainer {
    static let store = RemoteFilePersistenceStore()
}

actor RemoteFilePersistenceStore {
    private enum Key {
        static let pairedMacs = "pairedMacs"
        static let selectedMacID = "selectedMacID"
        static let initialSetupCompleted = RemotePersistenceClient.initialSetupCompletedKey
    }

    private let defaults: UserDefaults
    private let rootURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let removeDirectory: @Sendable (URL) throws -> Void
    private var appStateSequenceTracker = RemoteAppPersistenceSequenceTracker()
    private var tombstones: Set<UUID> = []

    init(
        defaultsSuiteName: String? = nil,
        rootURL: URL? = nil,
        removeDirectory: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) {
        self.defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.rootURL = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OnlySwitchRemote", isDirectory: true)
        self.removeDirectory = removeDirectory
    }

    func loadPairedMacs() throws -> [PairedMac] {
        guard let data = defaults.data(forKey: Key.pairedMacs) else { return [] }
        return try decoder.decode([PairedMac].self, from: data)
    }

    func savePairedMacs(_ macs: [PairedMac]) throws {
        defaults.set(try encoder.encode(macs.filter { tombstones.contains($0.id) == false }), forKey: Key.pairedMacs)
    }

    func upsertPairedMac(_ mac: PairedMac) throws {
        guard tombstones.contains(mac.id) == false else { return }
        var macs = try loadPairedMacs()
        macs.removeAll { $0.id == mac.id }
        macs.append(mac)
        try savePairedMacs(macs)
    }

    func updateRequiresPairing(_ id: UUID, value: Bool) throws {
        guard tombstones.contains(id) == false else { return }
        var macs = try loadPairedMacs()
        guard let index = macs.firstIndex(where: { $0.id == id }) else { return }
        macs[index].requiresPairing = value
        try savePairedMacs(macs)
    }

    func updateEndpoint(_ id: UUID, description: String?, connectedAt: Date?) throws {
        guard tombstones.contains(id) == false else { return }
        var macs = try loadPairedMacs()
        guard let index = macs.firstIndex(where: { $0.id == id }) else { return }
        macs[index].lastEndpointDescription = description
        macs[index].lastConnectedAt = connectedAt
        try savePairedMacs(macs)
    }

    func loadSelectedMacID() -> UUID? {
        defaults.string(forKey: Key.selectedMacID).flatMap(UUID.init(uuidString:))
    }

    func saveAppState(_ intent: RemoteAppPersistenceIntent) throws {
        guard appStateSequenceTracker.accepts(intent) else { return }
        defaults.set(intent.selectedMacID?.uuidString, forKey: Key.selectedMacID)
        defaults.set(intent.hasCompletedInitialSetup, forKey: Key.initialSetupCompleted)
    }

    func loadInitialSetupCompleted() -> Bool {
        defaults.bool(forKey: Key.initialSetupCompleted)
    }

    func saveInitialSetupCompleted(_ value: Bool) {
        defaults.set(value, forKey: Key.initialSetupCompleted)
    }

    func saveSelectedMacID(_ id: UUID?) {
        defaults.set(id?.uuidString, forKey: Key.selectedMacID)
    }

    func load<Value: Decodable>(_ type: Value.Type, macID: UUID, name: String) throws -> Value? {
        guard tombstones.contains(macID) == false else { return nil }
        let url = directory(for: macID).appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(type, from: Data(contentsOf: url, options: .mappedIfSafe))
    }

    func save<Value: Encodable>(_ value: Value, macID: UUID, name: String) throws {
        guard tombstones.contains(macID) == false else { return }
        let directory = directory(for: macID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(value).write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func mergeStatus(_ status: RemoteControlStatus, macID: UUID) throws {
        guard tombstones.contains(macID) == false else { return }
        var values = try load([RemoteControlStatus].self, macID: macID, name: "statuses.json") ?? []
        if let existing = values.first(where: { $0.id == status.id }), existing.revision > status.revision {
            return
        }
        values.removeAll { $0.id == status.id }
        values.append(status)
        try save(values, macID: macID, name: "statuses.json")
    }

    func mergeStatusSnapshot(_ incoming: [RemoteControlStatus], macID: UUID) throws {
        guard tombstones.contains(macID) == false else { return }
        let cached = try load([RemoteControlStatus].self, macID: macID, name: "statuses.json") ?? []
        let existing = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        let merged = incoming.map { value in
            guard let current = existing[value.id], current.revision > value.revision else { return value }
            return current
        }
        try save(merged, macID: macID, name: "statuses.json")
    }

    func removePreferences(_ id: UUID) throws {
        var macs = try loadPairedMacs()
        macs.removeAll { $0.id == id }
        try savePairedMacs(macs)
        if loadSelectedMacID() == id { saveSelectedMacID(nil) }
    }

    func removeCaches(_ id: UUID) throws {
        let directory = directory(for: id)
        if FileManager.default.fileExists(atPath: directory.path) {
            try removeDirectory(directory)
        }
    }

    func markTombstoned(_ id: UUID) { tombstones.insert(id) }

    func isTombstoned(_ id: UUID) -> Bool { tombstones.contains(id) }

    func commitPairing(_ mac: PairedMac) throws {
        let wasTombstoned = tombstones.contains(mac.id)
        tombstones.remove(mac.id)
        do {
            var macs = try loadPairedMacs()
            macs.removeAll { $0.id == mac.id }
            macs.append(mac)
            try savePairedMacs(macs)
        } catch {
            if wasTombstoned { tombstones.insert(mac.id) }
            throw error
        }
    }

    func commitPairingAndSelect(_ mac: PairedMac) throws -> RemotePairingPersistenceSnapshot {
        let snapshot = RemotePairingPersistenceSnapshot(
            previousMac: try loadPairedMacs().first { $0.id == mac.id },
            previousSelectedMacID: loadSelectedMacID(),
            wasTombstoned: tombstones.contains(mac.id)
        )
        try commitPairing(mac)
        saveSelectedMacID(mac.id)
        return snapshot
    }

    func restorePairingSnapshot(
        macID: UUID,
        snapshot: RemotePairingPersistenceSnapshot
    ) throws {
        var macs = try loadPairedMacs()
        macs.removeAll { $0.id == macID }
        if snapshot.wasTombstoned {
            tombstones.insert(macID)
        } else {
            tombstones.remove(macID)
            if let previousMac = snapshot.previousMac { macs.append(previousMac) }
        }
        try savePairedMacs(macs)
        saveSelectedMacID(snapshot.previousSelectedMacID)
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
