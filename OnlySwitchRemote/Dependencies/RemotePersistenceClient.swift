import Dependencies
import DependenciesMacros
import Foundation
import RemoteCore

@DependencyClient
struct RemotePersistenceClient: Sendable {
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
    var mergeStatus: @Sendable (UUID, RemoteControlStatus) async throws -> Void = { _, _ in throw RemoteDependencyError.unimplemented }
    var forgetMac: @Sendable (UUID) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
}

enum RemoteDependencyError: Swift.Error, Sendable { case unimplemented }

extension RemotePersistenceClient {
    static func inMemory() -> Self {
        let store = InMemoryRemotePersistenceStore()
        return Self(
            loadPairedMacs: { await store.pairedMacs },
            savePairedMacs: { await store.setPairedMacs($0) },
            upsertPairedMac: { await store.upsert($0) },
            updateRequiresPairing: { await store.updateRequiresPairing($0, value: $1) },
            updateEndpoint: { await store.updateEndpoint($0, description: $1, connectedAt: $2) },
            removePairedMac: { await store.removePairedMac($0) },
            loadSelectedMacID: { await store.selectedMacID },
            saveSelectedMacID: { await store.setSelectedMacID($0) },
            loadLayout: { await store.layouts[$0] },
            saveLayout: { await store.setLayout($0) },
            loadCatalog: { await store.catalogs[$0] },
            saveCatalog: { await store.setCatalog(.init(revision: $1, controls: $2), for: $0) },
            loadStatuses: { await store.statuses[$0] },
            saveStatuses: { await store.mergeSnapshot($1, for: $0) },
            mergeStatus: { await store.mergeStatus($1, for: $0) },
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
            mergeStatus: { try await store.mergeStatus($1, macID: $0) },
            forgetMac: { id in
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

private actor InMemoryRemotePersistenceStore {
    var pairedMacs: [PairedMac] = []
    var selectedMacID: UUID?
    var layouts: [UUID: MacDashboardLayout] = [:]
    var catalogs: [UUID: RemoteCatalogCache] = [:]
    var statuses: [UUID: [RemoteControlStatus]] = [:]

    func setPairedMacs(_ value: [PairedMac]) { pairedMacs = value }
    func upsert(_ value: PairedMac) {
        pairedMacs.removeAll { $0.id == value.id }
        pairedMacs.append(value)
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
        if selectedMacID == id { selectedMacID = nil }
    }
    func setSelectedMacID(_ value: UUID?) { selectedMacID = value }
    func setLayout(_ value: MacDashboardLayout) { layouts[value.macID] = value }
    func setCatalog(_ value: RemoteCatalogCache, for id: UUID) { catalogs[id] = value }
    func setStatuses(_ value: [RemoteControlStatus], for id: UUID) { statuses[id] = value }
    func mergeSnapshot(_ incoming: [RemoteControlStatus], for id: UUID) {
        let existing = Dictionary(uniqueKeysWithValues: (statuses[id] ?? []).map { ($0.id, $0) })
        statuses[id] = incoming.map { value in
            guard let cached = existing[value.id], cached.revision > value.revision else { return value }
            return cached
        }
    }
    func mergeStatus(_ value: RemoteControlStatus, for id: UUID) {
        var values = statuses[id] ?? []
        if let existing = values.first(where: { $0.id == value.id }), existing.revision > value.revision {
            return
        }
        values.removeAll { $0.id == value.id }
        values.append(value)
        statuses[id] = values
    }
    func forget(_ id: UUID) {
        pairedMacs.removeAll { $0.id == id }
        if selectedMacID == id { selectedMacID = nil }
        layouts[id] = nil
        catalogs[id] = nil
        statuses[id] = nil
    }
}

private enum RemotePersistenceLiveContainer {
    static let store = RemoteFilePersistenceStore()
}

actor RemoteFilePersistenceStore {
    private enum Key {
        static let pairedMacs = "pairedMacs"
        static let selectedMacID = "selectedMacID"
    }

    private let defaults: UserDefaults
    private let rootURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let removeDirectory: @Sendable (URL) throws -> Void

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
        defaults.set(try encoder.encode(macs), forKey: Key.pairedMacs)
    }

    func upsertPairedMac(_ mac: PairedMac) throws {
        var macs = try loadPairedMacs()
        macs.removeAll { $0.id == mac.id }
        macs.append(mac)
        try savePairedMacs(macs)
    }

    func updateRequiresPairing(_ id: UUID, value: Bool) throws {
        var macs = try loadPairedMacs()
        guard let index = macs.firstIndex(where: { $0.id == id }) else { return }
        macs[index].requiresPairing = value
        try savePairedMacs(macs)
    }

    func updateEndpoint(_ id: UUID, description: String?, connectedAt: Date?) throws {
        var macs = try loadPairedMacs()
        guard let index = macs.firstIndex(where: { $0.id == id }) else { return }
        macs[index].lastEndpointDescription = description
        macs[index].lastConnectedAt = connectedAt
        try savePairedMacs(macs)
    }

    func loadSelectedMacID() -> UUID? {
        defaults.string(forKey: Key.selectedMacID).flatMap(UUID.init(uuidString:))
    }

    func saveSelectedMacID(_ id: UUID?) {
        defaults.set(id?.uuidString, forKey: Key.selectedMacID)
    }

    func load<Value: Decodable>(_ type: Value.Type, macID: UUID, name: String) throws -> Value? {
        let url = directory(for: macID).appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(type, from: Data(contentsOf: url, options: .mappedIfSafe))
    }

    func save<Value: Encodable>(_ value: Value, macID: UUID, name: String) throws {
        let directory = directory(for: macID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(value).write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func mergeStatus(_ status: RemoteControlStatus, macID: UUID) throws {
        var values = try load([RemoteControlStatus].self, macID: macID, name: "statuses.json") ?? []
        if let existing = values.first(where: { $0.id == status.id }), existing.revision > status.revision {
            return
        }
        values.removeAll { $0.id == status.id }
        values.append(status)
        try save(values, macID: macID, name: "statuses.json")
    }

    func mergeStatusSnapshot(_ incoming: [RemoteControlStatus], macID: UUID) throws {
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

    private func directory(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }
}
