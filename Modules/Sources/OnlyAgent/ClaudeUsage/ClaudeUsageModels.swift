import Foundation

public struct ClaudeUsageAccount: Equatable, Sendable {
    public let email: String?
    public let plan: String?
    public init(email: String?, plan: String?) { self.email = email; self.plan = plan }
}

public struct ClaudeQuotaWindow: Equatable, Sendable {
    public let remainingPercent: Int
    public let resetAt: Date?
    public init(remainingPercent: Int, resetAt: Date?) {
        self.remainingPercent = min(max(remainingPercent, 0), 100); self.resetAt = resetAt
    }
    public static func remainingPercent(fromUsedPercent value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int((100 - min(max(value, 0), 100)).rounded())
    }
}

public struct ClaudeModelUsage: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let quota: ClaudeQuotaWindow
    public init(id: String, name: String, quota: ClaudeQuotaWindow) { self.id = id; self.name = name; self.quota = quota }
}

public struct ClaudeExtraUsage: Equatable, Sendable {
    public let isEnabled: Bool
    public let used: Double?
    public let limit: Double?
    public let currency: String?
    public let utilization: Double?
    public init(isEnabled: Bool, used: Double?, limit: Double?, currency: String?, utilization: Double?) {
        self.isEnabled = isEnabled; self.used = used; self.limit = limit; self.currency = currency; self.utilization = utilization
    }
}

public struct ClaudeUsageSnapshot: Equatable, Sendable {
    public let account: ClaudeUsageAccount
    public let session: ClaudeQuotaWindow?
    public let weekly: ClaudeQuotaWindow?
    public let models: [ClaudeModelUsage]
    public let extraUsage: ClaudeExtraUsage?
    public let fetchedAt: Date
    public init(account: ClaudeUsageAccount, session: ClaudeQuotaWindow?, weekly: ClaudeQuotaWindow?, models: [ClaudeModelUsage], extraUsage: ClaudeExtraUsage?, fetchedAt: Date) {
        self.account = account; self.session = session; self.weekly = weekly; self.models = models; self.extraUsage = extraUsage; self.fetchedAt = fetchedAt
    }
}

public enum ClaudeUsageError: Error, Equatable, Sendable {
    case signedOut, unauthorized, permissionDenied, network, rateLimited, invalidResponse, unsupported
}
