//
//  AuthenticatorModels.swift
//  OnlySwitch
//
//  Created by Codex.
//

import Foundation

public enum AuthenticatorAlgorithm: String, Codable, Sendable, CaseIterable {
    case sha1
    case sha256
    case sha512

    init(googleMigrationRawValue: Int) {
        switch googleMigrationRawValue {
        case 2: self = .sha256
        case 3: self = .sha512
        default: self = .sha1
        }
    }
}

public struct AuthenticatorAccount: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var issuer: String
    public var name: String
    public var customName: String?
    public var digits: Int
    public var period: Int
    public var algorithm: AuthenticatorAlgorithm
    public var secretKeychainKey: String
    public var createdAt: Date

    public init(
        id: UUID,
        issuer: String,
        name: String,
        customName: String? = nil,
        digits: Int,
        period: Int,
        algorithm: AuthenticatorAlgorithm,
        secretKeychainKey: String,
        createdAt: Date
    ) {
        self.id = id
        self.issuer = issuer
        self.name = name
        self.customName = customName
        self.digits = digits
        self.period = period
        self.algorithm = algorithm
        self.secretKeychainKey = secretKeychainKey
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, issuer, name, customName, digits, period, algorithm
        case secretKeychainKey, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        issuer = try container.decode(String.self, forKey: .issuer)
        name = try container.decode(String.self, forKey: .name)
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
        digits = try container.decode(Int.self, forKey: .digits)
        period = try container.decode(Int.self, forKey: .period)
        algorithm = try container.decode(AuthenticatorAlgorithm.self, forKey: .algorithm)
        secretKeychainKey = try container.decode(String.self, forKey: .secretKeychainKey)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    var displayName: String {
        let trimmedCustomName = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedCustomName, !trimmedCustomName.isEmpty {
            return trimmedCustomName
        }
        if issuer.isEmpty { return name }
        if name.isEmpty { return issuer }
        return "\(issuer) (\(name))"
    }

    func renamed(to proposedName: String) -> Self {
        var copy = self
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.customName = trimmedName.isEmpty ? nil : trimmedName
        return copy
    }
}

extension Array where Element == AuthenticatorAccount {
    mutating func renameAccount(id: UUID, to proposedName: String) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index] = self[index].renamed(to: proposedName)
    }
}
