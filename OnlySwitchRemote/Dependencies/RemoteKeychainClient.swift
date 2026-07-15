import Dependencies
import DependenciesMacros
import Foundation
import Security

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

    static var live: Self {
        Self(
            saveCredential: { id, credential in
                guard credential.count == 32 else { throw Error.invalidCredentialLength }
                let query = baseQuery(id)
                SecItemDelete(query as CFDictionary)
                var attributes = query
                attributes[kSecValueData as String] = credential
                attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                attributes[kSecAttrSynchronizable as String] = kCFBooleanFalse
                let status = SecItemAdd(attributes as CFDictionary, nil)
                guard status == errSecSuccess else { throw Error.status(status) }
            },
            loadCredential: { id in
                var query = baseQuery(id)
                query[kSecReturnData as String] = kCFBooleanTrue
                query[kSecMatchLimit as String] = kSecMatchLimitOne
                query[kSecAttrSynchronizable as String] = kCFBooleanFalse
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                if status == errSecItemNotFound { return nil }
                guard status == errSecSuccess, let data = result as? Data else { throw Error.status(status) }
                guard data.count == 32 else { throw Error.invalidCredentialLength }
                return data
            },
            deleteCredential: { id in
                let status = SecItemDelete(baseQuery(id) as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else { throw Error.status(status) }
            }
        )
    }

    private static func baseQuery(_ id: UUID) -> [String: Any] {
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
