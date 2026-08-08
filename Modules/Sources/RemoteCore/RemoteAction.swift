import Foundation

public enum RemoteControlAction: Codable, Equatable, Sendable {
    case setState(Bool)
    case trigger

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum Kind: String, Codable {
        case setState
        case trigger
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .setState:
            self = .setState(try container.decode(Bool.self, forKey: .value))
        case .trigger:
            self = .trigger
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .setState(isOn):
            try container.encode(Kind.setState, forKey: .type)
            try container.encode(isOn, forKey: .value)
        case .trigger:
            try container.encode(Kind.trigger, forKey: .type)
        }
    }
}

public struct RemoteActionRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let controlID: RemoteControlID
    public let action: RemoteControlAction

    public init(requestID: UUID, controlID: RemoteControlID, action: RemoteControlAction) {
        self.requestID = requestID
        self.controlID = controlID
        self.action = action
    }
}

public struct RemoteActionResult: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let result: Result<RemoteControlStatus?, RemoteProtocolError>

    private enum CodingKeys: String, CodingKey {
        case requestID
        case success
        case failure
    }

    public init(requestID: UUID, result: Result<RemoteControlStatus?, RemoteProtocolError>) {
        self.requestID = requestID
        self.result = result
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(UUID.self, forKey: .requestID)

        let hasSuccess = container.contains(.success)
        let hasFailure = container.contains(.failure)
        guard hasSuccess != hasFailure else {
            throw DecodingError.dataCorruptedError(
                forKey: .success,
                in: container,
                debugDescription: "Action result must contain exactly one of success or failure."
            )
        }

        if hasSuccess {
            result = .success(try container.decodeIfPresent(RemoteControlStatus.self, forKey: .success))
        } else {
            result = .failure(try container.decode(RemoteProtocolError.self, forKey: .failure))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        switch result {
        case let .success(status):
            try container.encodeIfPresent(status, forKey: .success)
            if status == nil {
                try container.encodeNil(forKey: .success)
            }
        case let .failure(error):
            try container.encode(error, forKey: .failure)
        }
    }
}
