import Foundation
import OnlyAgent
import RemoteCore

struct RemoteClaudeUsageProvider: Sendable {
    var fetch: @Sendable () async -> Result<RemoteClaudeUsageSnapshot, RemoteProtocolError>

    init(usageClient: ClaudeUsageClient) {
        fetch = {
            do {
                let usage = try await usageClient.fetch(false)
                return .success(.init(
                    account: .init(email: usage.account.email.map { String($0.prefix(320)) }, plan: usage.account.plan.map { String($0.prefix(128)) }),
                    session: usage.session.map { .init(remainingPercent: $0.remainingPercent, resetAt: $0.resetAt) },
                    weekly: usage.weekly.map { .init(remainingPercent: $0.remainingPercent, resetAt: $0.resetAt) },
                    models: usage.models.prefix(32).map { .init(id: String($0.id.prefix(128)), name: String($0.name.prefix(128)), quota: .init(remainingPercent: $0.quota.remainingPercent, resetAt: $0.quota.resetAt)) },
                    extraUsage: usage.extraUsage.map {
                        .init(isEnabled: $0.isEnabled, used: Self.nonnegativeFinite($0.used), limit: Self.nonnegativeFinite($0.limit), currency: $0.currency.map { String($0.prefix(16)) }, utilization: Self.nonnegativeFinite($0.utilization).map { min($0, 100) })
                    },
                    fetchedAt: usage.fetchedAt
                ))
            } catch let error as ClaudeUsageError {
                return .failure(Self.map(error))
            } catch {
                return .failure(.init(code: .executionFailed, message: "Claude usage is temporarily unavailable."))
            }
        }
    }

    static let live = Self(usageClient: .liveValue)

    private static func nonnegativeFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func map(_ error: ClaudeUsageError) -> RemoteProtocolError {
        switch error {
        case .signedOut, .unauthorized, .permissionDenied:
            .init(code: .authenticationFailed, message: "Sign in to Claude Code on the selected Mac.")
        case .network, .rateLimited:
            .init(code: .executionFailed, message: "Claude usage is temporarily unavailable.")
        case .invalidResponse:
            .init(code: .invalidFrame, message: "The Mac returned an invalid Claude usage response.")
        case .unsupported:
            .init(code: .actionNotSupported, message: "Claude usage is unavailable on this Mac.")
        }
    }
}
