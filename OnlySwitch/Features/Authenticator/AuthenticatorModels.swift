//
//  AuthenticatorModels.swift
//  OnlySwitch
//
//  Created by Codex.
//

import Foundation

enum AuthenticatorAlgorithm: String, Codable, Sendable, CaseIterable {
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

struct AuthenticatorAccount: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var issuer: String
    var name: String
    var digits: Int
    var period: Int
    var algorithm: AuthenticatorAlgorithm
    var secretKeychainKey: String
    var createdAt: Date

    var displayName: String {
        if issuer.isEmpty { return name }
        if name.isEmpty { return issuer }
        return "\(issuer) (\(name))"
    }
}

