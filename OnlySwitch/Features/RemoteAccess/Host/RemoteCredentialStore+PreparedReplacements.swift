import Foundation
import RemoteCore
import RemoteTransport
import Security

extension RemoteCredentialStore {
    static func decodeRecord(_ data: Data) throws -> PairedRemoteDevice {
        let record = try JSONDecoder().decode(PairedRemoteDevice.self, from: data)
        guard record.credential.count == 32 else { throw Error.invalidRecord }
        return record
    }

    func loadPreparedReplacement(_ transactionID: UUID) throws -> PreparedReplacement? {
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

    func loadPreparedReplacements() throws -> [UUID: PreparedReplacement] {
        switch backend {
        case .memory:
            return preparedReplacements
        case let .keychain(service):
            return try Dictionary(uniqueKeysWithValues: Self.loadAllData(
                service: Self.transactionService(for: service)
            ).map {
                let record = try Self.decodePreparedReplacement($0)
                return (record.transactionID, record)
            })
        }
    }

    func savePreparedReplacement(_ transaction: PreparedReplacement) throws {
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

    func makeTransactionCapacity(
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

    func saveRevocationVerifier(_ verifier: Data, for id: UUID) throws {
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

    func deleteRevocationVerifier(_ id: UUID) throws {
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

    static func revocationService(for credentialService: String) -> String {
        credentialService + ".revocations"
    }

    private static func transactionService(for credentialService: String) -> String {
        credentialService + ".pairing-transactions"
    }
}
