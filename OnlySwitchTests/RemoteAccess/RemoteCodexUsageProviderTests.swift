import Foundation
import OnlyAgent
import RemoteCore
import Testing
@testable import OnlySwitch

struct RemoteCodexUsageProviderTests {
    @Test func mapsEveryUsageFieldAndSkipsLocalScanWithoutOptIn() async throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionReset = Date(timeIntervalSince1970: 1_800_003_600)
        let weeklyReset = Date(timeIntervalSince1970: 1_800_604_800)
        let creditExpiry = Date(timeIntervalSince1970: 1_800_086_400)
        let scans = InvocationCounter()
        let provider = RemoteCodexUsageProvider(
            usageClient: .init(fetch: {
                CodexUsageSnapshot(
                    account: .init(email: "person@example.com", plan: "Team"),
                    session: .init(remainingPercent: 76, resetAt: sessionReset),
                    weekly: .init(remainingPercent: 44, resetAt: weeklyReset),
                    resetCredits: .available(count: 3, expiresAt: creditExpiry),
                    creditBalance: .available(remaining: 8.5, limit: 20, unit: "credits"),
                    source: .oauth,
                    fetchedAt: fetchedAt
                )
            }),
            localUsageClient: .init(scan: {
                await scans.record()
                return .init(dailyUsage: [], isPartial: false)
            })
        )

        let result = await provider.fetch(false)
        let snapshot = try result.get()

        #expect(snapshot.account == .init(email: "person@example.com", plan: "Team"))
        #expect(snapshot.session == .init(remainingPercent: 76, resetAt: sessionReset))
        #expect(snapshot.weekly == .init(remainingPercent: 44, resetAt: weeklyReset))
        #expect(snapshot.resetCredits == .available(count: 3, expiresAt: creditExpiry))
        #expect(snapshot.creditBalance == .available(remaining: 8.5, limit: 20, unit: "credits"))
        #expect(snapshot.source == .oauth)
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(snapshot.activity == nil)
        #expect(await scans.count == 0)
    }

    @Test func optInScansExactlyOnceAndAttachesLocalActivity() async throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let scans = InvocationCounter()
        let provider = RemoteCodexUsageProvider(
            usageClient: .init(fetch: { .fixture }),
            localUsageClient: .init(scan: {
                await scans.record()
                return .init(dailyUsage: [.init(date: date, tokenCount: 987)], isPartial: true)
            })
        )

        let snapshot = try await provider.fetch(true).get()

        #expect(await scans.count == 1)
        #expect(snapshot.activity == .init(
            dailyUsage: [.init(date: date, tokenCount: 987)],
            isPartial: true
        ))
    }

    @Test func optInScanFailureKeepsQuotaDataAndReportsPartialActivity() async throws {
        enum ScanFailure: Error { case unreadableFile }
        let provider = RemoteCodexUsageProvider(
            usageClient: .init(fetch: { .fixture }),
            localUsageClient: .init(scan: { throw ScanFailure.unreadableFile })
        )

        let snapshot = try await provider.fetch(true).get()

        #expect(snapshot.account.plan == "Plus")
        #expect(snapshot.activity == .init(dailyUsage: [], isPartial: true))
    }

    @Test(arguments: [
        (CodexUsageError.signedOut, RemoteProtocolError.Code.authenticationFailed),
        (.unauthorized, .authenticationFailed),
        (.network, .executionFailed),
        (.invalidResponse, .invalidFrame),
        (.unsupported, .actionNotSupported),
    ])
    func errorsMapToStableSanitizedProtocolCodes(
        _ input: (error: CodexUsageError, code: RemoteProtocolError.Code)
    ) async {
        let secret = "secret-token-should-not-escape"
        let provider = RemoteCodexUsageProvider(
            usageClient: .init(fetch: { throw input.error }),
            localUsageClient: .init(scan: {
                Issue.record("The local scanner must not run when usage fetch fails: \(secret)")
                return .init(dailyUsage: [], isPartial: false)
            })
        )

        let result = await provider.fetch(true)
        guard case let .failure(error) = result else {
            Issue.record("Expected a mapped protocol failure.")
            return
        }
        #expect(error.code == input.code)
        #expect(error.message.contains(secret) == false)
    }
}

private actor InvocationCounter {
    private(set) var count = 0
    func record() { count += 1 }
}

private extension CodexUsageSnapshot {
    static let fixture = Self(
        account: .init(email: nil, plan: "Plus"),
        session: nil,
        weekly: nil,
        resetCredits: .unavailable,
        creditBalance: .unavailable,
        source: .cli,
        fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}
