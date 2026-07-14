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

public enum RemoteMessage: Codable, Equatable, Sendable {
    case clientHello(ClientHello)
    case serverHello(ServerHello)
    case pairingRequest
    case pairingProof(PairingProof)
    case pairingResult(Result<PairingSuccess, RemoteProtocolError>)
    case authenticationProof(AuthenticationProof)
    case authenticationResult(Result<AuthenticationSuccess, RemoteProtocolError>)
    case catalogRequest
    case catalogSnapshot(revision: UInt64, controls: [RemoteControlDescriptor])
    case catalogChanged(revision: UInt64)
    case subscriptionUpdate(Set<RemoteControlID>)
    case statusSnapshot([RemoteControlStatus])
    case statusChanged(RemoteControlStatus)
    case actionRequest(RemoteActionRequest)
    case actionResult(RemoteActionResult)
    case ping(UInt64)
    case pong(UInt64)
    case sessionError(RemoteProtocolError)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
        case revision
        case controls
        case success
        case failure
    }

    private enum Kind: String, Codable {
        case clientHello
        case serverHello
        case pairingRequest
        case pairingProof
        case pairingResult
        case authenticationProof
        case authenticationResult
        case catalogRequest
        case catalogSnapshot
        case catalogChanged
        case subscriptionUpdate
        case statusSnapshot
        case statusChanged
        case actionRequest
        case actionResult
        case ping
        case pong
        case sessionError
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .clientHello:
            self = .clientHello(try container.decode(ClientHello.self, forKey: .payload))
        case .serverHello:
            self = .serverHello(try container.decode(ServerHello.self, forKey: .payload))
        case .pairingRequest:
            self = .pairingRequest
        case .pairingProof:
            self = .pairingProof(try container.decode(PairingProof.self, forKey: .payload))
        case .pairingResult:
            self = .pairingResult(try Self.decodeResult(PairingSuccess.self, from: container))
        case .authenticationProof:
            self = .authenticationProof(try container.decode(AuthenticationProof.self, forKey: .payload))
        case .authenticationResult:
            self = .authenticationResult(try Self.decodeResult(AuthenticationSuccess.self, from: container))
        case .catalogRequest:
            self = .catalogRequest
        case .catalogSnapshot:
            self = .catalogSnapshot(
                revision: try container.decode(UInt64.self, forKey: .revision),
                controls: try container.decode([RemoteControlDescriptor].self, forKey: .controls)
            )
        case .catalogChanged:
            self = .catalogChanged(revision: try container.decode(UInt64.self, forKey: .revision))
        case .subscriptionUpdate:
            self = .subscriptionUpdate(try container.decode(Set<RemoteControlID>.self, forKey: .payload))
        case .statusSnapshot:
            self = .statusSnapshot(try container.decode([RemoteControlStatus].self, forKey: .payload))
        case .statusChanged:
            self = .statusChanged(try container.decode(RemoteControlStatus.self, forKey: .payload))
        case .actionRequest:
            self = .actionRequest(try container.decode(RemoteActionRequest.self, forKey: .payload))
        case .actionResult:
            self = .actionResult(try container.decode(RemoteActionResult.self, forKey: .payload))
        case .ping:
            self = .ping(try container.decode(UInt64.self, forKey: .payload))
        case .pong:
            self = .pong(try container.decode(UInt64.self, forKey: .payload))
        case .sessionError:
            self = .sessionError(try container.decode(RemoteProtocolError.self, forKey: .payload))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .clientHello(value):
            try container.encode(Kind.clientHello, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .serverHello(value):
            try container.encode(Kind.serverHello, forKey: .type)
            try container.encode(value, forKey: .payload)
        case .pairingRequest:
            try container.encode(Kind.pairingRequest, forKey: .type)
        case let .pairingProof(value):
            try container.encode(Kind.pairingProof, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .pairingResult(result):
            try container.encode(Kind.pairingResult, forKey: .type)
            try Self.encodeResult(result, into: &container)
        case let .authenticationProof(value):
            try container.encode(Kind.authenticationProof, forKey: .type)
            try container.encode(value, forKey: .payload)
        case let .authenticationResult(result):
            try container.encode(Kind.authenticationResult, forKey: .type)
            try Self.encodeResult(result, into: &container)
        case .catalogRequest:
            try container.encode(Kind.catalogRequest, forKey: .type)
        case let .catalogSnapshot(revision, controls):
            try container.encode(Kind.catalogSnapshot, forKey: .type)
            try container.encode(revision, forKey: .revision)
            try container.encode(controls, forKey: .controls)
        case let .catalogChanged(revision):
            try container.encode(Kind.catalogChanged, forKey: .type)
            try container.encode(revision, forKey: .revision)
        case let .subscriptionUpdate(ids):
            try container.encode(Kind.subscriptionUpdate, forKey: .type)
            try container.encode(ids, forKey: .payload)
        case let .statusSnapshot(statuses):
            try container.encode(Kind.statusSnapshot, forKey: .type)
            try container.encode(statuses, forKey: .payload)
        case let .statusChanged(status):
            try container.encode(Kind.statusChanged, forKey: .type)
            try container.encode(status, forKey: .payload)
        case let .actionRequest(request):
            try container.encode(Kind.actionRequest, forKey: .type)
            try container.encode(request, forKey: .payload)
        case let .actionResult(result):
            try container.encode(Kind.actionResult, forKey: .type)
            try container.encode(result, forKey: .payload)
        case let .ping(nonce):
            try container.encode(Kind.ping, forKey: .type)
            try container.encode(nonce, forKey: .payload)
        case let .pong(nonce):
            try container.encode(Kind.pong, forKey: .type)
            try container.encode(nonce, forKey: .payload)
        case let .sessionError(error):
            try container.encode(Kind.sessionError, forKey: .type)
            try container.encode(error, forKey: .payload)
        }
    }

    private static func decodeResult<Success: Decodable>(
        _ successType: Success.Type,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Result<Success, RemoteProtocolError> {
        let hasSuccess = container.contains(.success)
        let hasFailure = container.contains(.failure)
        guard hasSuccess != hasFailure else {
            throw DecodingError.dataCorruptedError(
                forKey: .success,
                in: container,
                debugDescription: "Result message must contain exactly one of success or failure."
            )
        }
        if hasSuccess {
            return .success(try container.decode(successType, forKey: .success))
        }
        return .failure(try container.decode(RemoteProtocolError.self, forKey: .failure))
    }

    private static func encodeResult<Success: Encodable>(
        _ result: Result<Success, RemoteProtocolError>,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch result {
        case let .success(value):
            try container.encode(value, forKey: .success)
        case let .failure(error):
            try container.encode(error, forKey: .failure)
        }
    }
}
