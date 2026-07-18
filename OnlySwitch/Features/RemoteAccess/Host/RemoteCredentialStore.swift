import Foundation
import RemoteCore
import RemoteTransport
import Security

struct PairedRemoteDevice: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let credential: Data
    let createdAt: Date
    var lastConnectedAt: Date?
}

struct RemoteProvisionalPairingContext: Equatable, Sendable {
    let transactionID: UUID
    let record: PairedRemoteDevice
    let snapshot: RemotePairingSnapshot
    let expiresAt: Date
}

actor RemoteCredentialStore {
    enum AuthenticationRecord: Equatable, Sendable {
        case credential(PairedRemoteDevice)
        case revoked
        case missing
    }

    enum Error: Swift.Error, Equatable {
        case invalidCredential
        case keychain(OSStatus)
        case invalidRecord
    }

    private enum Backend: Sendable {
        case keychain(service: String)
        case memory
    }

    private struct PreparedReplacement: Codable, Sendable {
        enum State: String, Codable, Sendable {
            case prepared
            case committing
            case committed
            case aborted
        }

        let transactionID: UUID
        let candidate: PairedRemoteDevice
        var previous: PairedRemoteDevice?
        let expiresAt: Date
        let snapshot: RemotePairingSnapshot?
        var state: State
        var updatedAt: Date

        var publicState: PairingTransactionState {
            switch state {
            case .prepared: .prepared
            case .committing, .committed: .committed
            case .aborted: .aborted
            }
        }
    }

    private static let identityService = "jacklandrin.OnlySwitch.remote.identity"
    private static let identityAccount = "installation-id"
    private static let maximumTransactions = 32

    private let backend: Backend
    private let finalizeRepairObserver: @Sendable (UUID) -> Void
    private let beforeRevocationDelete: @Sendable () throws -> Void
    private var records: [UUID: PairedRemoteDevice] = [:]
    private var revocationVerifiers: [UUID: Data] = [:]
    private var preparedReplacements: [UUID: PreparedReplacement] = [:]
    private var memoryInstallationID: UUID?

    private init(
        backend: Backend,
        finalizeRepairObserver: @escaping @Sendable (UUID) -> Void = { _ in },
        beforeRevocationDelete: @escaping @Sendable () throws -> Void = {},
        records: [UUID: PairedRemoteDevice] = [:],
        revocationVerifiers: [UUID: Data] = [:],
        preparedReplacements: [UUID: PreparedReplacement] = [:]
    ) {
        self.backend = backend
        self.finalizeRepairObserver = finalizeRepairObserver
        self.beforeRevocationDelete = beforeRevocationDelete
        self.records = records
        self.revocationVerifiers = revocationVerifiers
        self.preparedReplacements = preparedReplacements
    }

    static func live(service: String = "jacklandrin.OnlySwitch.remote.devices") -> RemoteCredentialStore {
        RemoteCredentialStore(backend: .keychain(service: service))
    }

    static func inMemory(
        finalizeRepairObserver: @escaping @Sendable (UUID) -> Void = { _ in },
        beforeRevocationDelete: @escaping @Sendable () throws -> Void = {}
    ) -> RemoteCredentialStore {
        RemoteCredentialStore(
            backend: .memory,
            finalizeRepairObserver: finalizeRepairObserver,
            beforeRevocationDelete: beforeRevocationDelete
        )
    }

    func restartedInMemoryForTesting() -> RemoteCredentialStore {
        RemoteCredentialStore(
            backend: .memory,
            records: records,
            revocationVerifiers: revocationVerifiers,
            preparedReplacements: preparedReplacements
        )
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

    func prepareReplacement(
        _ candidate: PairedRemoteDevice,
        transactionID: UUID,
        expiresAt: Date,
        snapshot: RemotePairingSnapshot? = nil
    ) throws {
        guard candidate.credential.count == 32 else { throw Error.invalidCredential }
        try recoverExpiredTransactions(now: .now)
        var transactions = try loadPreparedReplacements()

        if let existing = transactions[transactionID] {
            guard existing.candidate == candidate else { throw Self.authenticationFailure() }
            guard existing.state != .aborted else { throw Self.authenticationFailure() }
            return
        }
        guard transactions.values.contains(where: {
            $0.candidate.id == candidate.id && ($0.state == .prepared || $0.state == .committing)
        }) == false else {
            throw Self.authenticationFailure()
        }

        try makeTransactionCapacity(in: &transactions)
        let record = PreparedReplacement(
            transactionID: transactionID,
            candidate: candidate,
            previous: try load(candidate.id),
            expiresAt: expiresAt,
            snapshot: snapshot,
            state: .prepared,
            updatedAt: .now
        )
        try savePreparedReplacement(record)
    }

    func provisionalPairingContext(
        deviceID: UUID,
        credential: Data
    ) throws -> RemoteProvisionalPairingContext? {
        try preparedPairingContexts(deviceID: deviceID).first {
            Self.constantTimeEqual($0.record.credential, credential)
        }
    }

    func preparedPairingContexts(deviceID: UUID) throws -> [RemoteProvisionalPairingContext] {
        try recoverExpiredTransactions(now: .now)
        return try loadPreparedReplacements().values.compactMap {
            $0.state == .prepared
                && $0.candidate.id == deviceID
                && $0.expiresAt > Date()
                && $0.snapshot != nil
            ? RemoteProvisionalPairingContext(
                transactionID: $0.transactionID,
                record: $0.candidate,
                snapshot: $0.snapshot!,
                expiresAt: $0.expiresAt
            )
            : nil
        }.sorted { $0.transactionID.uuidString < $1.transactionID.uuidString }
    }

    @discardableResult
    func finalizePrepared(_ transactionID: UUID) throws -> PairedRemoteDevice {
        guard var transaction = try loadPreparedReplacement(transactionID) else {
            throw Self.authenticationFailure()
        }
        switch transaction.state {
        case .committed:
            return transaction.candidate
        case .aborted:
            throw Self.authenticationFailure()
        case .committing:
            try save(transaction.candidate)
            transaction.state = .committed
            transaction.previous = nil
            transaction.updatedAt = .now
            try savePreparedReplacement(transaction)
            return transaction.candidate
        case .prepared:
            guard transaction.expiresAt > Date() else {
                transaction.state = .aborted
                transaction.previous = nil
                transaction.updatedAt = .now
                try savePreparedReplacement(transaction)
                throw Self.authenticationFailure()
            }
            transaction.state = .committing
            transaction.updatedAt = .now
            try savePreparedReplacement(transaction)
            try save(transaction.candidate)
            transaction.state = .committed
            transaction.previous = nil
            transaction.updatedAt = .now
            try savePreparedReplacement(transaction)
            return transaction.candidate
        }
    }

    func abortPrepared(_ transactionID: UUID) throws {
        guard var transaction = try loadPreparedReplacement(transactionID) else {
            throw Self.authenticationFailure()
        }
        switch transaction.state {
        case .prepared:
            transaction.state = .aborted
            transaction.previous = nil
            transaction.updatedAt = .now
            try savePreparedReplacement(transaction)
        case .committing:
            _ = try finalizePrepared(transactionID)
        case .committed, .aborted:
            return
        }
    }

    func transactionStatus(_ transactionID: UUID) throws -> PairingTransactionState {
        try recoverExpiredTransactions(now: .now)
        guard let transaction = try loadPreparedReplacement(transactionID) else {
            throw Self.authenticationFailure()
        }
        return transaction.publicState
    }

    func transactionStatus(
        _ transactionID: UUID,
        deviceID: UUID,
        credential: Data
    ) throws -> PairingTransactionState {
        try recoverExpiredTransactions(now: .now)
        guard let transaction = try loadPreparedReplacement(transactionID),
              transaction.candidate.id == deviceID,
              Self.constantTimeEqual(transaction.candidate.credential, credential) else {
            throw Self.authenticationFailure()
        }
        return transaction.publicState
    }

    func transactionRetainsPreviousCredentialForTesting(_ transactionID: UUID) throws -> Bool {
        try loadPreparedReplacement(transactionID)?.previous != nil
    }

    func recoverExpiredTransactions(now: Date = .now) throws {
        let transactions = try loadPreparedReplacements()
        for var transaction in transactions.values {
            switch transaction.state {
            case .prepared where transaction.expiresAt <= now:
                transaction.state = .aborted
                transaction.previous = nil
                transaction.updatedAt = now
                try savePreparedReplacement(transaction)
            case .committing:
                try save(transaction.candidate)
                transaction.state = .committed
                transaction.previous = nil
                transaction.updatedAt = now
                try savePreparedReplacement(transaction)
            default:
                break
            }
        }
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

    @discardableResult
    func revoke(_ id: UUID, matchingCredential credential: Data? = nil) throws -> Bool {
        guard let preparedCredential = try prepareRevocation(id, matchingCredential: credential) else {
            return try loadRevocationVerifier(id) != nil
        }
        try delete(id, matchingCredential: preparedCredential)
        return true
    }

    func prepareRevocation(_ id: UUID, matchingCredential credential: Data? = nil) throws -> Data? {
        try abortActiveReplacements(for: id)
        guard let current = try load(id) else { return nil }
        if let credential,
           Self.constantTimeEqual(current.credential, credential) == false {
            return nil
        }
        let verifier = RemoteHandshakeCrypto.revocationVerifier(credential: current.credential)
        try saveRevocationVerifier(verifier, for: id)
        return current.credential
    }

    func prepareAndDeleteForRevocation(_ id: UUID) throws -> Data? {
        guard let credential = try prepareRevocation(id) else { return nil }
        try beforeRevocationDelete()
        try delete(id, matchingCredential: credential)
        return credential
    }

    private func abortActiveReplacements(for deviceID: UUID) throws {
        let transactions = try loadPreparedReplacements()
        for var transaction in transactions.values where transaction.candidate.id == deviceID {
            switch transaction.state {
            case .prepared:
                transaction.state = .aborted
                transaction.previous = nil
                transaction.updatedAt = .now
                try savePreparedReplacement(transaction)
            case .committing:
                if let current = try load(deviceID),
                   Self.constantTimeEqual(current.credential, transaction.candidate.credential) {
                    if let previous = transaction.previous {
                        try save(previous)
                    } else {
                        try delete(deviceID)
                    }
                }
                transaction.state = .aborted
                transaction.previous = nil
                transaction.updatedAt = .now
                try savePreparedReplacement(transaction)
            case .committed, .aborted:
                break
            }
        }
    }

    func loadRevocationVerifier(_ id: UUID) throws -> Data? {
        switch backend {
        case .memory:
            return revocationVerifiers[id]
        case let .keychain(service):
            return try Self.loadData(service: Self.revocationService(for: service), account: id.uuidString)
        }
    }

    func authenticationRecord(_ id: UUID) throws -> AuthenticationRecord {
        let record = try load(id)
        let verifier = try loadRevocationVerifier(id)
        if let record {
            if let verifier,
               Self.constantTimeEqual(
                RemoteHandshakeCrypto.revocationVerifier(credential: record.credential),
                verifier
               ) {
                return .revoked
            }
            return .credential(record)
        }
        return verifier == nil ? .missing : .revoked
    }

    func finalizeRepair(deviceID: UUID, matchingCredential credential: Data) throws {
        guard let current = try load(deviceID),
              Self.constantTimeEqual(current.credential, credential),
              try loadRevocationVerifier(deviceID) != nil else { return }
        try deleteRevocationVerifier(deviceID)
        finalizeRepairObserver(deviceID)
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

    private func loadPreparedReplacement(_ transactionID: UUID) throws -> PreparedReplacement? {
        switch backend {
        case .memory:
            return preparedReplacements[transactionID]
        case let .keychain(service):
            guard let data = try Self.loadData(
                service: Self.transactionService(for: service),
                account: transactionID.uuidString
            ) else { return nil }
            return try Self.decodePreparedReplacement(data)
        }
    }

    private func loadPreparedReplacements() throws -> [UUID: PreparedReplacement] {
        switch backend {
        case .memory:
            return preparedReplacements
        case let .keychain(service):
            var query = Self.baseQuery(service: Self.transactionService(for: service))
            query[kSecMatchLimit] = kSecMatchLimitAll
            query[kSecReturnData] = true
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return [:] }
            guard status == errSecSuccess else { throw Error.keychain(status) }
            let dataItems = (result as? [Data]) ?? (result as? Data).map { [$0] } ?? []
            return try Dictionary(uniqueKeysWithValues: dataItems.map {
                let record = try Self.decodePreparedReplacement($0)
                return (record.transactionID, record)
            })
        }
    }

    private func savePreparedReplacement(_ transaction: PreparedReplacement) throws {
        switch backend {
        case .memory:
            preparedReplacements[transaction.transactionID] = transaction
        case let .keychain(service):
            try Self.upsert(
                data: try JSONEncoder().encode(transaction),
                service: Self.transactionService(for: service),
                account: transaction.transactionID.uuidString
            )
        }
    }

    private func deletePreparedReplacement(_ transactionID: UUID) throws {
        switch backend {
        case .memory:
            preparedReplacements[transactionID] = nil
        case let .keychain(service):
            let status = SecItemDelete(Self.baseQuery(
                service: Self.transactionService(for: service),
                account: transactionID.uuidString
            ) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw Error.keychain(status)
            }
        }
    }

    private func makeTransactionCapacity(
        in transactions: inout [UUID: PreparedReplacement]
    ) throws {
        while transactions.count >= Self.maximumTransactions {
            guard let evicted = transactions.values
                .filter({ $0.state == .committed || $0.state == .aborted })
                .min(by: { $0.updatedAt < $1.updatedAt }) else {
                throw Self.authenticationFailure()
            }
            try deletePreparedReplacement(evicted.transactionID)
            transactions[evicted.transactionID] = nil
        }
    }

    private static func decodePreparedReplacement(_ data: Data) throws -> PreparedReplacement {
        let transaction = try JSONDecoder().decode(PreparedReplacement.self, from: data)
        guard transaction.candidate.credential.count == 32,
              transaction.previous?.credential.count == nil || transaction.previous?.credential.count == 32 else {
            throw Error.invalidRecord
        }
        return transaction
    }

    private func saveRevocationVerifier(_ verifier: Data, for id: UUID) throws {
        guard verifier.count == 32 else { throw Error.invalidCredential }
        switch backend {
        case .memory:
            revocationVerifiers[id] = verifier
        case let .keychain(service):
            try Self.upsert(
                data: verifier,
                service: Self.revocationService(for: service),
                account: id.uuidString
            )
        }
    }

    private func deleteRevocationVerifier(_ id: UUID) throws {
        switch backend {
        case .memory:
            revocationVerifiers[id] = nil
        case let .keychain(service):
            let status = SecItemDelete(Self.baseQuery(
                service: Self.revocationService(for: service),
                account: id.uuidString
            ) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Error.keychain(status) }
        }
    }

    private static func revocationService(for credentialService: String) -> String {
        credentialService + ".revocations"
    }

    private static func transactionService(for credentialService: String) -> String {
        credentialService + ".pairing-transactions"
    }

    private static func authenticationFailure() -> RemoteProtocolError {
        RemoteProtocolError(code: .authenticationFailed, message: "Pairing transaction is unavailable")
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
