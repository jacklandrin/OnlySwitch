import Foundation
public struct RemoteClaudeUsageRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public init(requestID: UUID) {
        self.requestID = requestID
    }
}

public struct ClaudeUsageAccountDTO: Codable, Equatable, Sendable {
    public let email: String?
    public let plan: String?
    public init(email: String?, plan: String?) {
        self.email = email
        self.plan = plan
    }
}

public struct ClaudeQuotaWindowDTO: Codable, Equatable, Sendable {
    public let remainingPercent: Int
    public let resetAt: Date?
    public init(remainingPercent: Int, resetAt: Date?) {
        self.remainingPercent = min(max(remainingPercent, 0), 100)
        self.resetAt = resetAt
    }
}

public struct ClaudeModelUsageDTO: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let quota: ClaudeQuotaWindowDTO
    public init(id: String, name: String, quota: ClaudeQuotaWindowDTO) {
        self.id = id
        self.name = name
        self.quota = quota
    }
}

public struct ClaudeExtraUsageDTO: Codable, Equatable, Sendable {
    public let isEnabled: Bool
    public let used: Double?
    public let limit: Double?
    public let currency: String?
    public let utilization: Double?
    public init(isEnabled: Bool, used: Double?, limit: Double?, currency: String?, utilization: Double?) {
        self.isEnabled = isEnabled
        self.used = used
        self.limit = limit
        self.currency = currency
        self.utilization = utilization
    }
}

public struct RemoteClaudeUsageSnapshot: Codable, Equatable, Sendable {
    public let account: ClaudeUsageAccountDTO
    public let session: ClaudeQuotaWindowDTO?
    public let weekly: ClaudeQuotaWindowDTO?
    public let models: [ClaudeModelUsageDTO]
    public let extraUsage: ClaudeExtraUsageDTO?
    public let fetchedAt: Date
    public init(account: ClaudeUsageAccountDTO, session: ClaudeQuotaWindowDTO?, weekly: ClaudeQuotaWindowDTO?, models: [ClaudeModelUsageDTO], extraUsage: ClaudeExtraUsageDTO?, fetchedAt: Date) {
        self.account = account
        self.session = session
        self.weekly = weekly
        self.models = models
        self.extraUsage = extraUsage
        self.fetchedAt = fetchedAt
    }
}

public struct RemoteClaudeUsageResult: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let result: Result<RemoteClaudeUsageSnapshot, RemoteProtocolError>
    public init(requestID: UUID, result: Result<RemoteClaudeUsageSnapshot, RemoteProtocolError>) {
        self.requestID = requestID; self.result = result
    }
    private enum CodingKeys: String, CodingKey { case requestID, success, failure }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        let hasSuccess = container.contains(.success), hasFailure = container.contains(.failure)
        guard hasSuccess != hasFailure else {
            throw DecodingError.dataCorruptedError(forKey: .success, in: container, debugDescription: "Result must contain exactly one of success or failure.")
        }
        result = hasSuccess
            ? .success(try container.decode(RemoteClaudeUsageSnapshot.self, forKey: .success))
            : .failure(try container.decode(RemoteProtocolError.self, forKey: .failure))
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        switch result {
        case let .success(value): try container.encode(value, forKey: .success)
        case let .failure(error): try container.encode(error, forKey: .failure)
        }
    }
}
