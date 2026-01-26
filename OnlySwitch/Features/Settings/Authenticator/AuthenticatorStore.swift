//
//  AuthenticatorStore.swift
//  OnlySwitch
//

import Foundation
import Extensions

@MainActor
final class AuthenticatorStore: ObservableObject {
    static let shared = AuthenticatorStore()

    private let keychainService = "com.jacklandrin.OnlySwitch.Authenticator"
    private lazy var keychain = KeychainManager(service: keychainService)

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: UserDefaults.Key.authenticatorEnabled)
            UserDefaults.standard.synchronize()
        }
    }

    @Published private(set) var accounts: [AuthenticatorAccount] {
        didSet { persistAccounts() }
    }

    private var secretCache: [UUID: Data] = [:]

    private init() {
        self.enabled = UserDefaults.standard.bool(forKey: UserDefaults.Key.authenticatorEnabled)
        self.accounts = Self.loadAccounts()
    }

    func reload() {
        secretCache = [:]
        accounts = Self.loadAccounts()
        enabled = UserDefaults.standard.bool(forKey: UserDefaults.Key.authenticatorEnabled)
    }

    func importFromScanResult(_ input: String) throws -> Int {
        let tokens = try OtpAuthImport.parse(input: input)
        guard !tokens.isEmpty else { return 0 }

        var existingFingerprints = Set<String>()
        for account in accounts {
            if let secretBase64 = try? keychain.retrieve(key: account.secretKeychainKey) ?? "" {
                existingFingerprints.insert(Self.fingerprint(
                    issuer: account.issuer,
                    name: account.name,
                    secretBase64: secretBase64,
                    digits: account.digits,
                    period: account.period,
                    algorithm: account.algorithm
                ))
            }
        }

        var added = 0
        var updatedAccounts = accounts

        for token in tokens {
            let secretBase64 = token.secret.base64EncodedString()
            let fp = Self.fingerprint(
                issuer: token.issuer,
                name: token.name,
                secretBase64: secretBase64,
                digits: token.digits,
                period: token.period,
                algorithm: token.algorithm
            )
            guard !existingFingerprints.contains(fp) else { continue }

            let id = UUID()
            let key = "totp.\(id.uuidString)"
            try keychain.save(key: key, value: secretBase64)

            let account = AuthenticatorAccount(
                id: id,
                issuer: token.issuer,
                name: token.name,
                digits: token.digits,
                period: token.period,
                algorithm: token.algorithm,
                secretKeychainKey: key,
                createdAt: Date()
            )
            updatedAccounts.append(account)
            existingFingerprints.insert(fp)
            added += 1
        }

        updatedAccounts.sort { $0.createdAt < $1.createdAt }
        secretCache = [:]
        accounts = updatedAccounts
        return added
    }

    func deleteAccount(_ account: AuthenticatorAccount) {
        accounts.removeAll { $0.id == account.id }
        try? keychain.delete(key: account.secretKeychainKey)
        secretCache.removeValue(forKey: account.id)
    }

    func deleteAll() {
        for account in accounts {
            try? keychain.delete(key: account.secretKeychainKey)
        }
        accounts = []
        secretCache = [:]
    }

    func secret(for account: AuthenticatorAccount) -> Data? {
        if let cached = secretCache[account.id] { return cached }
        guard let secretBase64 = try? keychain.retrieve(key: account.secretKeychainKey) ?? "" else { return nil }
        guard !secretBase64.isEmpty, let data = Data(base64Encoded: secretBase64) else { return nil }
        secretCache[account.id] = data
        return data
    }

    private static func loadAccounts() -> [AuthenticatorAccount] {
        guard let data = UserDefaults.standard.data(forKey: UserDefaults.Key.authenticatorAccounts) else { return [] }
        return (try? JSONDecoder().decode([AuthenticatorAccount].self, from: data)) ?? []
    }

    private func persistAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: UserDefaults.Key.authenticatorAccounts)
        UserDefaults.standard.synchronize()
    }

    private static func fingerprint(
        issuer: String,
        name: String,
        secretBase64: String,
        digits: Int,
        period: Int,
        algorithm: AuthenticatorAlgorithm
    ) -> String {
        "\(issuer.lowercased())|\(name.lowercased())|\(secretBase64)|\(digits)|\(period)|\(algorithm.rawValue)"
    }
}
