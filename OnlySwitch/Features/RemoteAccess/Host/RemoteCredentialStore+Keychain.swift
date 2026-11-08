import Foundation
import os
import RemoteCore
import RemoteTransport
import Security

extension RemoteCredentialStore {
    static func authenticationFailure() -> RemoteProtocolError {
        RemoteProtocolError(code: .authenticationFailed, message: "Pairing transaction is unavailable")
    }

    // The legacy file-based keychain guards each item with an ACL bound to the creating code
    // signature, so every rebuild or signing-identity change re-prompts for the login password.
    // Signed builds carry a keychain access group and can use the Data Protection keychain,
    // which has no per-item ACL prompts; unsigned builds fall back to the legacy keychain.
    static let usesDataProtectionKeychain: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(
            task,
            "keychain-access-groups" as CFString,
            nil
        ) != nil
    }()

    private static let migratedServices = OSAllocatedUnfairLock(initialState: Set<String>())

    static func baseQuery(service: String, account: String? = nil) -> [CFString: Any] {
        if usesDataProtectionKeychain { migrateLegacyItemsIfNeeded(service: service) }
        return keychainQuery(
            service: service,
            account: account,
            usesDataProtectionKeychain: usesDataProtectionKeychain
        )
    }

    // Items paired before the Data Protection keychain switch live in the legacy keychain, which
    // the Data Protection queries cannot see. Move them over once per service and process so
    // existing pairings and the installation ID survive the upgrade. Items already present in the
    // Data Protection keychain win, and failures are left in place to be retried on next launch.
    private static func migrateLegacyItemsIfNeeded(service: String) {
        migratedServices.withLock { migrated in
            guard migrated.insert(service).inserted else { return }
            migrateLegacyItems(service: service)
        }
    }

    static func migrateLegacyItems(service: String) {
        var listQuery = keychainQuery(service: service, usesDataProtectionKeychain: false)
        listQuery[kSecMatchLimit] = kSecMatchLimitAll
        listQuery[kSecReturnAttributes] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(listQuery as CFDictionary, &result) == errSecSuccess else { return }
        let items = (result as? [[CFString: Any]]) ?? (result as? [CFString: Any]).map { [$0] } ?? []

        for account in items.compactMap({ $0[kSecAttrAccount] as? String }) {
            let legacyQuery = keychainQuery(
                service: service,
                account: account,
                usesDataProtectionKeychain: false
            )
            var dataQuery = legacyQuery
            dataQuery[kSecMatchLimit] = kSecMatchLimitOne
            dataQuery[kSecReturnData] = true
            var data: CFTypeRef?
            guard SecItemCopyMatching(dataQuery as CFDictionary, &data) == errSecSuccess,
                  let data = data as? Data else { continue }

            var insert = keychainQuery(service: service, account: account, usesDataProtectionKeychain: true)
            insert[kSecValueData] = data
            insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else { continue }
            SecItemDelete(legacyQuery as CFDictionary)
        }
    }

    static func keychainQuery(
        service: String,
        account: String? = nil,
        usesDataProtectionKeychain: Bool
    ) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrSynchronizable: kCFBooleanFalse as Any
        ]
        if let account { query[kSecAttrAccount] = account }
        query[kSecUseDataProtectionKeychain] = usesDataProtectionKeychain
        return query
    }

    static func loadData(service: String, account: String) throws -> Data? {
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

    static func loadAllData(service: String) throws -> [Data] {
        var query = baseQuery(service: service)
        query[kSecMatchLimit] = kSecMatchLimitAll
        query[kSecReturnAttributes] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw Error.keychain(status) }

        let attributes: [[CFString: Any]]
        if let items = result as? [[CFString: Any]] {
            attributes = items
        } else if let item = result as? [CFString: Any] {
            attributes = [item]
        } else {
            throw Error.invalidRecord
        }
        return try attributes.map { item in
            guard let account = item[kSecAttrAccount] as? String,
                  let data = try loadData(service: service, account: account) else {
                throw Error.invalidRecord
            }
            return data
        }
    }

    static func upsert(data: Data, service: String, account: String) throws {
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

    static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
        return difference == 0
    }
}
