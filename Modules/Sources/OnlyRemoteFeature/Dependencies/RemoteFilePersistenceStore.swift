import Darwin
import Foundation
import RemoteCore

enum RemotePersistenceLiveContainer {
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
    private var hasSynchronizedRootParent = false

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

    func replaceAphroditeLibrary(_ snapshot: AphroditeRemoteLibrarySnapshot, macID: UUID) throws {
        let validated = try snapshot.validated()
        if let current = try load(AphroditeRemoteLibrarySnapshot.self, macID: macID, name: "aphrodite-library.json"),
           current.revision >= validated.revision { return }
        try save(validated, macID: macID, name: "aphrodite-library.json")
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
        credentialVerifier: Data
    ) throws -> PreparedPairingPersistenceRecord {
        try mutateEnvelope { envelope in
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

    func preparePairingState(
        _ candidate: PairedMac,
        transactionID: UUID,
        credentialIdentity: Data
    ) throws -> PreparedPairingPersistenceRecord {
        try preparePairingState(candidate, transactionID: transactionID, credentialVerifier: credentialIdentity)
    }

    func loadPreparedPairingState() throws -> PreparedPairingPersistenceRecord? {
        try loadEnvelope().preparedPairing
    }

    func adoptPreparedPairingState(_ transactionID: UUID) throws {
        try mutateEnvelope {
            guard var prepared = $0.preparedPairing,
                  prepared.transactionID == transactionID else {
                throw RemotePersistenceError.transactionMismatch
            }
            if prepared.phase == .adopted { return }
            prepared.phase = .adopted
            $0.preparedPairing = prepared
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
            let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
            let envelope = try decoder.decode(
                RemotePersistentStateEnvelope.self,
                from: bytes
            )
            guard envelope.version == 1 else {
                throw RemotePersistenceError.unsupportedEnvelopeVersion(envelope.version)
            }
            if bytes.range(of: Data("\"candidateCredentialIdentity\"".utf8)) != nil {
                try saveEnvelope(envelope)
            }
            if defaults.integer(forKey: Key.migratedEnvelopeVersion) < 1 {
                try synchronizeRootParentIfNeeded()
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
        try synchronizeRootParentIfNeeded()
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

    private func synchronizeRootParentIfNeeded() throws {
        guard hasSynchronizedRootParent == false else { return }
        try synchronizeEnvelopeDirectory(rootURL.deletingLastPathComponent())
        hasSynchronizedRootParent = true
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

struct RemoteAppPersistenceSequenceTracker {
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
