import Dependencies
import DependenciesMacros
import CryptoKit
import Foundation
import Security

struct RemoteKeychainOperations: Sendable {
    var update: @Sendable (UUID, Data) async -> OSStatus
    var add: @Sendable (UUID, Data) async -> OSStatus
    var load: @Sendable (UUID) async -> (OSStatus, Data?)
    var delete: @Sendable (UUID) async -> OSStatus
    var deleteIfMatches: @Sendable (UUID, Data) async -> (OSStatus, Bool)

    static func security(service: String) -> Self { Self(
        update: { id, data in
            SecItemUpdate(
                RemoteKeychainClient.baseQuery(id, service: service) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
        },
        add: { id, data in
            var attributes = RemoteKeychainClient.baseQuery(id, service: service)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(attributes as CFDictionary, nil)
        },
        load: { id in
            var query = RemoteKeychainClient.baseQuery(id, service: service)
            query[kSecReturnData as String] = kCFBooleanTrue
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result as? Data)
        },
        delete: { SecItemDelete(RemoteKeychainClient.baseQuery($0, service: service) as CFDictionary) },
        deleteIfMatches: { id, expected in
            var query = RemoteKeychainClient.baseQuery(id, service: service)
            query[kSecReturnData as String] = kCFBooleanTrue
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let loadStatus = SecItemCopyMatching(query as CFDictionary, &result)
            if loadStatus == errSecItemNotFound { return (errSecSuccess, false) }
            guard loadStatus == errSecSuccess, let current = result as? Data else {
                return (loadStatus, false)
            }
            guard RemoteKeychainClient.constantTimeEqual(current, expected) else {
                return (errSecSuccess, false)
            }
            let deleteStatus = SecItemDelete(RemoteKeychainClient.baseQuery(id, service: service) as CFDictionary)
            return (deleteStatus, deleteStatus == errSecSuccess)
        }
    ) }
}

@DependencyClient
struct RemoteKeychainClient: Sendable {
    enum Error: Swift.Error, Equatable, Sendable {
        case invalidCredentialLength
        case status(OSStatus)
    }

    var saveCredential: @Sendable (UUID, Data) async throws -> Void = { _, _ in throw RemoteDependencyError.unimplemented }
    var loadCredential: @Sendable (UUID) async throws -> Data? = { _ in nil }
    var deleteCredential: @Sendable (UUID) async throws -> Void = { _ in throw RemoteDependencyError.unimplemented }
    var deleteCredentialIfMatches: @Sendable (UUID, Data) async throws -> Bool = { _, _ in throw RemoteDependencyError.unimplemented }
    var saveProvisionalCredential: @Sendable (UUID, Data) async throws -> Void = { _, _ in throw RemoteDependencyError.unimplemented }
    var loadProvisionalCredential: @Sendable (UUID) async throws -> Data? = { _ in nil }
    var deleteProvisionalCredential: @Sendable (UUID, Data) async throws -> Bool = { _, _ in throw RemoteDependencyError.unimplemented }
    var promoteProvisionalCredential: @Sendable (UUID, UUID, Data) async throws -> Bool = { _, _, _ in
        throw RemoteDependencyError.unimplemented
    }
}

extension RemoteKeychainClient {
    static let service = "jacklandrin.OnlySwitchRemote.macs"
    static let provisionalService = "jacklandrin.OnlySwitchRemote.pairing-transactions"

    static func inMemory() -> Self {
        let store = InMemoryRemoteCredentialStore()
        return Self(
            saveCredential: { id, credential in
                guard credential.count == 32 else { throw Error.invalidCredentialLength }
                await store.save(credential, for: id)
            },
            loadCredential: { await store.load($0) },
            deleteCredential: { await store.delete($0) },
            deleteCredentialIfMatches: { await store.delete($0, matching: $1) },
            saveProvisionalCredential: { id, credential in
                guard credential.count == 32 else { throw Error.invalidCredentialLength }
                await store.saveProvisional(credential, for: id)
            },
            loadProvisionalCredential: { await store.loadProvisional($0) },
            deleteProvisionalCredential: { await store.deleteProvisional($0, verifier: $1) },
            promoteProvisionalCredential: { await store.promote($0, to: $1, verifier: $2) }
        )
    }

    init(
        saveCredential: @escaping @Sendable (UUID, Data) async throws -> Void,
        loadCredential: @escaping @Sendable (UUID) async throws -> Data?,
        deleteCredential: @escaping @Sendable (UUID) async throws -> Void,
        deleteCredentialIfMatches: @escaping @Sendable (UUID, Data) async throws -> Bool
    ) {
        let provisional = RemoteKeychainClient.inMemory()
        self.init(
            saveCredential: saveCredential,
            loadCredential: loadCredential,
            deleteCredential: deleteCredential,
            deleteCredentialIfMatches: deleteCredentialIfMatches,
            saveProvisionalCredential: provisional.saveCredential,
            loadProvisionalCredential: provisional.loadCredential,
            deleteProvisionalCredential: { transactionID, verifier in
                guard let raw = try await provisional.loadCredential(transactionID) else { return true }
                guard RemoteKeychainClient.credentialVerifier(raw) == verifier else { return false }
                return try await provisional.deleteCredentialIfMatches(transactionID, raw)
            },
            promoteProvisionalCredential: { transactionID, macID, verifier in
                if let raw = try await provisional.loadCredential(transactionID) {
                    guard RemoteKeychainClient.credentialVerifier(raw) == verifier else { return false }
                    try await saveCredential(macID, raw)
                    return try await provisional.deleteCredentialIfMatches(transactionID, raw)
                }
                guard let committed = try await loadCredential(macID) else { return false }
                return RemoteKeychainClient.credentialVerifier(committed) == verifier
            }
        )
    }

    static var live: Self { RemoteKeychainLiveContainer.client }

    static func live(operations: RemoteKeychainOperations) -> Self {
        let store = RemoteKeychainStore(operations: operations)
        return client(store: store, provisional: store)
    }

    fileprivate static func client(store: RemoteKeychainStore, provisional: RemoteKeychainStore) -> Self {
        Self(
            saveCredential: { id, credential in
                guard credential.count == 32 else { throw Error.invalidCredentialLength }
                try await store.save(id, credential: credential)
            },
            loadCredential: { try await store.load($0) },
            deleteCredential: { try await store.delete($0) },
            deleteCredentialIfMatches: { id, expected in
                guard expected.count == 32 else { throw Error.invalidCredentialLength }
                return try await store.delete(id, matching: expected)
            },
            saveProvisionalCredential: { id, credential in
                guard credential.count == 32 else { throw Error.invalidCredentialLength }
                try await provisional.save(id, credential: credential)
            },
            loadProvisionalCredential: { try await provisional.load($0) },
            deleteProvisionalCredential: { id, verifier in
                guard let raw = try await provisional.load(id) else { return true }
                guard credentialVerifier(raw) == verifier else { return false }
                return try await provisional.delete(id, matching: raw)
            },
            promoteProvisionalCredential: { transactionID, macID, verifier in
                if let raw = try await provisional.load(transactionID) {
                    guard credentialVerifier(raw) == verifier else { return false }
                    try await store.save(macID, credential: raw)
                    return try await provisional.delete(transactionID, matching: raw)
                }
                guard let committed = try await store.load(macID) else { return false }
                return credentialVerifier(committed) == verifier
            }
        )
    }

    fileprivate static func baseQuery(_ id: UUID, service: String = service) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString.lowercased(),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    static func credentialVerifier(_ credential: Data) -> Data {
        Data(SHA256.hash(data: credential))
    }

    fileprivate static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
        return difference == 0
    }
}

private enum RemoteKeychainLiveContainer {
    static let committed = RemoteKeychainStore(operations: .security(service: RemoteKeychainClient.service))
    static let provisional = RemoteKeychainStore(operations: .security(service: RemoteKeychainClient.provisionalService))
    static let client = RemoteKeychainClient.client(store: committed, provisional: provisional)
}

private actor RemoteKeychainStore {
    private let operations: RemoteKeychainOperations

    init(operations: RemoteKeychainOperations) {
        self.operations = operations
    }

    func save(_ id: UUID, credential: Data) async throws {
        let updateStatus = await operations.update(id, credential)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw RemoteKeychainClient.Error.status(updateStatus) }
        let status = await operations.add(id, credential)
        guard status == errSecSuccess else { throw RemoteKeychainClient.Error.status(status) }
    }

    func load(_ id: UUID) async throws -> Data? {
        let (status, data) = await operations.load(id)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data else { throw RemoteKeychainClient.Error.status(status) }
        guard data.count == 32 else { throw RemoteKeychainClient.Error.invalidCredentialLength }
        return data
    }

    func delete(_ id: UUID) async throws {
        let status = await operations.delete(id)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RemoteKeychainClient.Error.status(status)
        }
    }

    func delete(_ id: UUID, matching expected: Data) async throws -> Bool {
        let (status, deleted) = await operations.deleteIfMatches(id, expected)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RemoteKeychainClient.Error.status(status)
        }
        return deleted
    }
}

extension RemoteKeychainClient: DependencyKey {
    static var liveValue: Self { .live }
    static var testValue: Self { Self() }
}

extension DependencyValues {
    var remoteKeychain: RemoteKeychainClient {
        get { self[RemoteKeychainClient.self] }
        set { self[RemoteKeychainClient.self] = newValue }
    }
}

private actor InMemoryRemoteCredentialStore {
    private var credentials: [UUID: Data] = [:]
    private var provisional: [UUID: Data] = [:]
    func save(_ credential: Data, for id: UUID) { credentials[id] = credential }
    func load(_ id: UUID) -> Data? { credentials[id] }
    func delete(_ id: UUID) { credentials[id] = nil }
    func delete(_ id: UUID, matching expected: Data) -> Bool {
        guard let current = credentials[id], RemoteKeychainClient.constantTimeEqual(current, expected) else {
            return false
        }
        credentials[id] = nil
        return true
    }
    func saveProvisional(_ credential: Data, for id: UUID) { provisional[id] = credential }
    func loadProvisional(_ id: UUID) -> Data? { provisional[id] }
    func deleteProvisional(_ id: UUID, verifier: Data) -> Bool {
        guard let raw = provisional[id] else { return true }
        guard RemoteKeychainClient.credentialVerifier(raw) == verifier else { return false }
        provisional[id] = nil
        return true
    }
    func promote(_ transactionID: UUID, to macID: UUID, verifier: Data) -> Bool {
        if let raw = provisional[transactionID] {
            guard RemoteKeychainClient.credentialVerifier(raw) == verifier else { return false }
            credentials[macID] = raw
            provisional[transactionID] = nil
            return true
        }
        guard let committed = credentials[macID] else { return false }
        return RemoteKeychainClient.credentialVerifier(committed) == verifier
    }
}
