import Foundation
import Security

struct PairedRemoteDevice: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let credential: Data
    let createdAt: Date
    var lastConnectedAt: Date?
}

actor RemoteCredentialStore {
    enum Error: Swift.Error, Equatable {
        case invalidCredential
        case keychain(OSStatus)
        case invalidRecord
    }

    private enum Backend: Sendable {
        case keychain(service: String)
        case memory
    }

    private static let identityService = "jacklandrin.OnlySwitch.remote.identity"
    private static let identityAccount = "installation-id"

    private let backend: Backend
    private var records: [UUID: PairedRemoteDevice] = [:]
    private var memoryInstallationID: UUID?

    private init(backend: Backend) {
        self.backend = backend
    }

    static func live(service: String = "jacklandrin.OnlySwitch.remote.devices") -> RemoteCredentialStore {
        RemoteCredentialStore(backend: .keychain(service: service))
    }

    static func inMemory() -> RemoteCredentialStore {
        RemoteCredentialStore(backend: .memory)
    }

    func save(_ device: PairedRemoteDevice) throws {
        guard device.credential.count == 32 else { throw Error.invalidCredential }
        switch backend {
        case .memory:
            records[device.id] = device
        case let .keychain(service):
            let data = try JSONEncoder().encode(device)
            try Self.upsert(data: data, service: service, account: device.id.uuidString)
        }
    }

    func replace(with device: PairedRemoteDevice) throws -> PairedRemoteDevice? {
        let previous = try load(device.id)
        try save(device)
        return previous
    }

    func rollbackReplacement(
        _ replacement: PairedRemoteDevice,
        previous: PairedRemoteDevice?,
        restorePrevious: Bool
    ) throws {
        guard let current = try load(replacement.id),
              Self.constantTimeEqual(current.credential, replacement.credential) else { return }
        if restorePrevious, let previous {
            try save(previous)
        } else {
            try delete(replacement.id)
        }
    }

    func delete(_ id: UUID, matchingCredential credential: Data) throws {
        guard let current = try load(id),
              Self.constantTimeEqual(current.credential, credential) else { return }
        try delete(id)
    }

    func load(_ id: UUID) throws -> PairedRemoteDevice? {
        switch backend {
        case .memory:
            return records[id]
        case let .keychain(service):
            guard let data = try Self.loadData(service: service, account: id.uuidString) else { return nil }
            return try Self.decodeRecord(data)
        }
    }

    func loadAll() throws -> [PairedRemoteDevice] {
        switch backend {
        case .memory:
            return records.values.sorted { $0.createdAt < $1.createdAt }
        case let .keychain(service):
            var query = Self.baseQuery(service: service)
            query[kSecMatchLimit] = kSecMatchLimitAll
            query[kSecReturnData] = true
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return [] }
            guard status == errSecSuccess else { throw Error.keychain(status) }
            let dataItems = (result as? [Data]) ?? (result as? Data).map { [$0] } ?? []
            return try dataItems.map(Self.decodeRecord).sorted { $0.createdAt < $1.createdAt }
        }
    }

    func delete(_ id: UUID) throws {
        switch backend {
        case .memory:
            records[id] = nil
        case let .keychain(service):
            let status = SecItemDelete(Self.baseQuery(service: service, account: id.uuidString) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Error.keychain(status) }
        }
    }

    func markConnected(deviceID: UUID, credential: Data, at date: Date) throws -> PairedRemoteDevice {
        guard var record = try load(deviceID), Self.constantTimeEqual(record.credential, credential) else {
            throw Error.invalidCredential
        }
        record.lastConnectedAt = date
        try save(record)
        return record
    }

    func installationID() throws -> UUID {
        switch backend {
        case .memory:
            if let memoryInstallationID { return memoryInstallationID }
            let id = UUID()
            memoryInstallationID = id
            return id
        case .keychain:
            if let data = try Self.loadData(service: Self.identityService, account: Self.identityAccount),
               let string = String(data: data, encoding: .utf8),
               let id = UUID(uuidString: string) {
                return id
            }
            let id = UUID()
            try Self.upsert(
                data: Data(id.uuidString.utf8),
                service: Self.identityService,
                account: Self.identityAccount
            )
            return id
        }
    }

    private static func decodeRecord(_ data: Data) throws -> PairedRemoteDevice {
        let record = try JSONDecoder().decode(PairedRemoteDevice.self, from: data)
        guard record.credential.count == 32 else { throw Error.invalidRecord }
        return record
    }

    private static func baseQuery(service: String, account: String? = nil) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrSynchronizable: kCFBooleanFalse as Any
        ]
        if let account { query[kSecAttrAccount] = account }
        return query
    }

    private static func loadData(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Error.keychain(status) }
        guard let data = result as? Data else { throw Error.invalidRecord }
        return data
    }

    private static func upsert(data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let update: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable: kCFBooleanFalse as Any
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw Error.keychain(updateStatus) }
        var insert = query
        update.forEach { insert[$0] = $1 }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Error.keychain(addStatus) }
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
        return difference == 0
    }
}
