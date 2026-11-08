import Foundation

public struct ClientHello: Codable, Equatable, Sendable {
    public let version: RemoteProtocolVersion
    public let deviceID: UUID
    public let deviceName: String
    public let ephemeralPublicKey: Data

    public init(version: RemoteProtocolVersion, deviceID: UUID, deviceName: String, ephemeralPublicKey: Data) {
        self.version = version
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.ephemeralPublicKey = ephemeralPublicKey
    }
}

public struct ServerHello: Codable, Equatable, Sendable {
    public let version: RemoteProtocolVersion
    public let macID: UUID
    public let macName: String
    public let ephemeralPublicKey: Data
    public let challenge: Data

    public init(version: RemoteProtocolVersion, macID: UUID, macName: String, ephemeralPublicKey: Data, challenge: Data) {
        self.version = version
        self.macID = macID
        self.macName = macName
        self.ephemeralPublicKey = ephemeralPublicKey
        self.challenge = challenge
    }
}

public struct PairingProof: Codable, Equatable, Sendable {
    public let deviceID: UUID
    public let proof: Data

    public init(deviceID: UUID, proof: Data) {
        self.deviceID = deviceID
        self.proof = proof
    }
}

public struct PairingSuccess: Codable, Equatable, Sendable {
    public let macID: UUID
    public let credential: Data

    public init(macID: UUID, credential: Data) {
        self.macID = macID
        self.credential = credential
    }
}

public struct PairingPrepared: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let macID: UUID
    public let credential: Data
    public let catalogRevision: UInt64
    public let expiresAt: Date

    public init(transactionID: UUID, macID: UUID, credential: Data, catalogRevision: UInt64, expiresAt: Date) {
        self.transactionID = transactionID
        self.macID = macID
        self.credential = credential
        self.catalogRevision = catalogRevision
        self.expiresAt = expiresAt
    }
}

public struct PairingTransactionCommand: Codable, Equatable, Sendable {
    public let transactionID: UUID

    public init(transactionID: UUID) {
        self.transactionID = transactionID
    }
}

public enum PairingTransactionState: String, Codable, Equatable, Sendable {
    case prepared, committed, aborted
}

public struct PairingTransactionStatus: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let state: PairingTransactionState

    public init(transactionID: UUID, state: PairingTransactionState) {
        self.transactionID = transactionID
        self.state = state
    }
}

public struct AuthenticationProof: Codable, Equatable, Sendable {
    public let deviceID: UUID
    public let proof: Data

    public init(deviceID: UUID, proof: Data) {
        self.deviceID = deviceID
        self.proof = proof
    }
}

public struct AuthenticationSuccess: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let catalogRevision: UInt64

    public init(sessionID: UUID, catalogRevision: UInt64) {
        self.sessionID = sessionID
        self.catalogRevision = catalogRevision
    }
}

public struct CredentialRevocationProof: Codable, Equatable, Sendable {
    public let deviceID: UUID
    public let proof: Data

    public init(deviceID: UUID, proof: Data) {
        self.deviceID = deviceID
        self.proof = proof
    }
}
