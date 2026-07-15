import Dependencies
import DependenciesMacros
import Foundation
import Security

struct RemoteKeychainOperations: Sendable {
    var update: @Sendable (UUID, Data) async -> OSStatus
    var add: @Sendable (UUID, Data) async -> OSStatus
    var load: @Sendable (UUID) async -> (OSStatus, Data?)
    var delete: @Sendable (UUID) async -> OSStatus
    var deleteIfMatches: @Sendable (UUID, Data) async -> (OSStatus, Bool)

    static let security = Self(
        update: { id, data in
            SecItemUpdate(
                RemoteKeychainClient.baseQuery(id) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
        },
        add: { id, data in
            var attributes = RemoteKeychainClient.baseQuery(id)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(attributes as CFDictionary, nil)
        },
        load: { id in
            var query = RemoteKeychainClient.baseQuery(id)
            query[kSecReturnData as String] = kCFBooleanTrue
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result as? Data)
        },
        delete: { SecItemDelete(RemoteKeychainClient.baseQuery($0) as CFDictionary) },
        deleteIfMatches: { id, expected in
            var query = RemoteKeychainClient.baseQuery(id)
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
            let deleteStatus = SecItemDelete(RemoteKeychainClient.baseQuery(id) as CFDictionary)
            return (deleteStatus, deleteStatus == errSecSuccess)
        }
    )
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
}

extension RemoteKeychainClient {
    static let service = "jacklandrin.OnlySwitchRemote.macs"

    static func inMemory() -> Self {
        let store = InMemoryRemoteCredentialStore()
        return Self(
            saveCredential: { id, credential in
                guard credential.count == 32 else { throw Error.invalidCredentialLength }
                await store.save(credential, for: id)
            },
            loadCredential: { await store.load($0) },
            deleteCredential: { await store.delete($0) },
            deleteCredentialIfMatches: { await store.delete($0, matching: $1) }
        )
    }

    static var live: Self { client(store: RemoteKeychainLiveContainer.store) }

    static func live(operations: RemoteKeychainOperations) -> Self {
        client(store: RemoteKeychainStore(operations: operations))
    }

    private static func client(store: RemoteKeychainStore) -> Self {
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
            }
        )
    }

    fileprivate static func baseQuery(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString.lowercased(),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    fileprivate static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
        return difference == 0
    }
}

private enum RemoteKeychainLiveContainer {
    static let store = RemoteKeychainStore(operations: .security)
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
}
