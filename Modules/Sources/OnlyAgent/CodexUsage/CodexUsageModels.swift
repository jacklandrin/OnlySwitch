import Foundation

public struct CodexUsageAccount: Equatable, Sendable {
    public let email: String?
    public let plan: String?

    public init(email: String?, plan: String?) {
        self.email = email
        self.plan = plan
    }
}

public struct CodexQuotaWindow: Equatable, Sendable {
    public let remainingPercent: Int
    public let resetAt: Date?

    public init(remainingPercent: Int, resetAt: Date?) {
        self.remainingPercent = min(max(remainingPercent, 0), 100)
        self.resetAt = resetAt
    }

    public static func remainingPercent(fromUsedPercent usedPercent: Double) -> Int {
        min(max(Int((100 - usedPercent).rounded()), 0), 100)
    }
}

public enum CodexResetCredits: Equatable, Sendable {
    case unavailable
    case unlimited
    case available(count: Int, expiresAt: Date?)

    public var isAvailable: Bool {
        switch self {
        case .unavailable: false
        case .unlimited, .available: true
        }
    }
}

public enum CodexCreditBalance: Equatable, Sendable {
    case unavailable
    case unlimited
    case available(remaining: Double, limit: Double?, unit: String)
}

public enum CodexUsageSource: Equatable, Sendable {
    case oauth
    case cli
}

public struct CodexDailyUsage: Equatable, Sendable, Identifiable {
    public let date: Date
    public let tokenCount: Int

    public var id: Date { date }

    public init(date: Date, tokenCount: Int) {
        self.date = date
        self.tokenCount = tokenCount
    }
}

public struct CodexActivityEstimate: Equatable, Sendable {
    public let dailyUsage: [CodexDailyUsage]
    public let isPartial: Bool

    public init(dailyUsage: [CodexDailyUsage], isPartial: Bool) {
        self.dailyUsage = dailyUsage
        self.isPartial = isPartial
    }

    public var todayTokenCount: Int {
        dailyUsage.first(where: { Calendar.current.isDateInToday($0.date) })?.tokenCount ?? 0
    }

    public var thirtyDayTokenCount: Int { dailyUsage.reduce(0) { $0 + $1.tokenCount } }
}

public struct CodexUsageSnapshot: Equatable, Sendable {
    public let account: CodexUsageAccount
    public let session: CodexQuotaWindow?
    public let weekly: CodexQuotaWindow?
    public let resetCredits: CodexResetCredits
    public let creditBalance: CodexCreditBalance
    public let source: CodexUsageSource
    public let fetchedAt: Date
    public let activity: CodexActivityEstimate?

    public init(
        account: CodexUsageAccount,
        session: CodexQuotaWindow?,
        weekly: CodexQuotaWindow?,
        resetCredits: CodexResetCredits,
        creditBalance: CodexCreditBalance = .unavailable,
        source: CodexUsageSource,
        fetchedAt: Date,
        activity: CodexActivityEstimate? = nil
    ) {
        self.account = account
        self.session = session
        self.weekly = weekly
        self.resetCredits = resetCredits
        self.creditBalance = creditBalance
        self.source = source
        self.fetchedAt = fetchedAt
        self.activity = activity
    }
}

public enum CodexUsageError: Error, Equatable, Sendable {
    case signedOut
    case unauthorized
    case network
    case invalidResponse
    case unsupported
}
