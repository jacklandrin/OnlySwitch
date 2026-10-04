import Foundation
import OnlyAgent
import RemoteCore

struct RemoteCodexUsageProvider: Sendable {
    var fetch: @Sendable (Bool) async -> Result<RemoteCodexUsageSnapshot, RemoteProtocolError>

    init(
        usageClient: CodexUsageClient,
        localUsageClient: CodexLocalUsageClient
    ) {
        fetch = { includeLocalActivity in
            do {
                let usage = try await usageClient.fetch()
                let activity: CodexActivityEstimate?
                if includeLocalActivity {
                    do {
                        activity = try await localUsageClient.scan()
                    } catch {
                        activity = .init(dailyUsage: [], isPartial: true)
                    }
                } else {
                    activity = nil
                }
                return .success(Self.map(usage, activity: activity))
            } catch let error as CodexUsageError {
                return .failure(Self.map(error))
            } catch {
                return .failure(.init(code: .executionFailed, message: "Codex usage is temporarily unavailable."))
            }
        }
    }

    static let live = Self(usageClient: .liveValue, localUsageClient: .liveValue)

    private static func map(_ usage: CodexUsageSnapshot, activity: CodexActivityEstimate?) -> RemoteCodexUsageSnapshot {
        let resetCredits: CodexResetCreditsDTO
        switch usage.resetCredits {
        case .unavailable: resetCredits = .unavailable
        case .unlimited: resetCredits = .unlimited
        case let .available(count, expiresAt): resetCredits = .available(count: count, expiresAt: expiresAt)
        }
        let creditBalance: CodexCreditBalanceDTO
        switch usage.creditBalance {
        case .unavailable: creditBalance = .unavailable
        case .unlimited: creditBalance = .unlimited
        case let .available(remaining, limit, unit): creditBalance = .available(remaining: remaining, limit: limit, unit: unit)
        }
        return .init(
            account: .init(email: usage.account.email, plan: usage.account.plan),
            session: usage.session.map { .init(remainingPercent: $0.remainingPercent, resetAt: $0.resetAt) },
            weekly: usage.weekly.map { .init(remainingPercent: $0.remainingPercent, resetAt: $0.resetAt) },
            resetCredits: resetCredits,
            creditBalance: creditBalance,
            source: usage.source == .oauth ? .oauth : .cli,
            fetchedAt: usage.fetchedAt,
            activity: activity.map {
                .init(
                    dailyUsage: $0.dailyUsage.map { .init(date: $0.date, tokenCount: $0.tokenCount) },
                    isPartial: $0.isPartial
                )
            }
        )
    }

    private static func map(_ error: CodexUsageError) -> RemoteProtocolError {
        switch error {
        case .signedOut, .unauthorized:
            .init(code: .authenticationFailed, message: "Sign in to Codex on the selected Mac.")
        case .network:
            .init(code: .executionFailed, message: "Codex usage is temporarily unavailable.")
        case .invalidResponse:
            .init(code: .invalidFrame, message: "The Mac returned an invalid Codex usage response.")
        case .unsupported:
            .init(code: .actionNotSupported, message: "Codex usage is unavailable on this Mac.")
        }
    }
}
