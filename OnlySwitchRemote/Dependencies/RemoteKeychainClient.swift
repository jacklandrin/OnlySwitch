import Dependencies
import DependenciesMacros
import Foundation
import Security

struct RemoteKeychainOperations: Sendable {
    var update: @Sendable (UUID, Data) async -> OSStatus
    var add: @Sendable (UUID, Data) async -> OSStatus
    var load: @Sendable (UUID) async -> (OSStatus, Data?)
    var delete: @Sendable (UUID) async -> OSStatus

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
        delete: { SecItemDelete(RemoteKeychainClient.baseQuery($0) as CFDictionary) }
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
            deleteCredential: { await store.delete($0) }
        )
    }

    static var live: Self { live(operations: .security) }

    static func live(operations: RemoteKeychainOperations) -> Self {
        Self(
            saveCredential: { id, credential in
                guard credential.count == 32 else { throw Error.invalidCredentialLength }
                let updateStatus = await operations.update(id, credential)
                if updateStatus == errSecSuccess { return }
                guard updateStatus == errSecItemNotFound else { throw Error.status(updateStatus) }
                let status = await operations.add(id, credential)
                guard status == errSecSuccess else { throw Error.status(status) }
            },
            loadCredential: { id in
                let (status, data) = await operations.load(id)
                if status == errSecItemNotFound { return nil }
                guard status == errSecSuccess, let data else { throw Error.status(status) }
                guard data.count == 32 else { throw Error.invalidCredentialLength }
                return data
            },
            deleteCredential: { id in
                let status = await operations.delete(id)
                guard status == errSecSuccess || status == errSecItemNotFound else { throw Error.status(status) }
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
}
