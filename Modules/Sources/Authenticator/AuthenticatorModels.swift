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
    public var digits: Int
    public var period: Int
    public var algorithm: AuthenticatorAlgorithm
    public var secretKeychainKey: String
    public var createdAt: Date

    var displayName: String {
        if issuer.isEmpty { return name }
        if name.isEmpty { return issuer }
        return "\(issuer) (\(name))"
    }
}
