import Foundation

public struct RemoteCodexUsageRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let includeLocalActivity: Bool
    public init(requestID: UUID, includeLocalActivity: Bool) {
        self.requestID = requestID
        self.includeLocalActivity = includeLocalActivity
    }
}

public struct CodexUsageAccountDTO: Codable, Equatable, Sendable {
    public let email: String?
    public let plan: String?
    public init(email: String?, plan: String?) { self.email = email; self.plan = plan }
}

public struct CodexQuotaWindowDTO: Codable, Equatable, Sendable {
    public let remainingPercent: Int
    public let resetAt: Date?
    public init(remainingPercent: Int, resetAt: Date?) {
        self.remainingPercent = min(max(remainingPercent, 0), 100)
        self.resetAt = resetAt
    }
}

public enum CodexResetCreditsDTO: Codable, Equatable, Sendable {
    case unavailable
    case unlimited
    case available(count: Int, expiresAt: Date?)
}

public enum CodexCreditBalanceDTO: Codable, Equatable, Sendable {
    case unavailable
    case unlimited
    case available(remaining: Double, limit: Double?, unit: String)
}

public enum CodexUsageSourceDTO: String, Codable, Equatable, Sendable { case oauth, cli }

public struct CodexDailyUsageDTO: Codable, Equatable, Sendable, Identifiable {
    public let date: Date
    public let tokenCount: Int
    public var id: Date { date }
    public init(date: Date, tokenCount: Int) { self.date = date; self.tokenCount = tokenCount }
}

public struct CodexActivityEstimateDTO: Codable, Equatable, Sendable {
    public let dailyUsage: [CodexDailyUsageDTO]
    public let isPartial: Bool
    public init(dailyUsage: [CodexDailyUsageDTO], isPartial: Bool) {
        self.dailyUsage = dailyUsage; self.isPartial = isPartial
    }
}

public struct RemoteCodexUsageSnapshot: Codable, Equatable, Sendable {
    public let account: CodexUsageAccountDTO
    public let session: CodexQuotaWindowDTO?
    public let weekly: CodexQuotaWindowDTO?
    public let resetCredits: CodexResetCreditsDTO
    public let creditBalance: CodexCreditBalanceDTO
    public let source: CodexUsageSourceDTO
    public let fetchedAt: Date
    public let activity: CodexActivityEstimateDTO?
    public init(account: CodexUsageAccountDTO, session: CodexQuotaWindowDTO?, weekly: CodexQuotaWindowDTO?, resetCredits: CodexResetCreditsDTO, creditBalance: CodexCreditBalanceDTO, source: CodexUsageSourceDTO, fetchedAt: Date, activity: CodexActivityEstimateDTO?) {
        self.account = account; self.session = session; self.weekly = weekly
        self.resetCredits = resetCredits; self.creditBalance = creditBalance
        self.source = source; self.fetchedAt = fetchedAt; self.activity = activity
    }
}

public struct RemoteCodexUsageResult: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let result: Result<RemoteCodexUsageSnapshot, RemoteProtocolError>
    public init(requestID: UUID, result: Result<RemoteCodexUsageSnapshot, RemoteProtocolError>) {
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
            ? .success(try container.decode(RemoteCodexUsageSnapshot.self, forKey: .success))
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
