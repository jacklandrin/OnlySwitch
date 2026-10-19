import Foundation
import OnlyAgent
import RemoteCore
import Testing
@testable import OnlySwitch

struct RemoteClaudeUsageProviderTests {
    @Test func snapshotKeepsRemoteAccountAndModelMetadataBounded() async throws {
        let longValue = String(repeating: "x", count: 500)
        let provider = RemoteClaudeUsageProvider(usageClient: .init(fetch: { _ in
            .init(account: .init(email: longValue, plan: longValue),
                  session: nil, weekly: nil,
                  models: (0..<40).map { index in
                      .init(id: "\(index)-" + longValue, name: longValue, quota: .init(remainingPercent: 50, resetAt: nil))
                  },
                  extraUsage: .init(isEnabled: true, used: 12.5, limit: 50, currency: longValue, utilization: 25),
                  fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        }))
        let snapshot = try await provider.fetch().get()
        #expect(snapshot.models.count == 32)
        #expect(snapshot.models.allSatisfy { $0.id.count <= 128 && $0.name.count <= 128 })
        #expect(snapshot.account.email?.count == 320)
        #expect(snapshot.account.plan?.count == 128)
        #expect(snapshot.extraUsage?.currency?.count == 16)
    }

    @Test func mapsReportedQuotaModelAndExtraUsageWithoutPrompting() async throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = RemoteClaudeUsageProvider(usageClient: .init(fetch: { allowPrompt in
            #expect(allowPrompt == false)
            return .init(
                account: .init(email: "fixture@example.com", plan: "Max"),
                session: .init(remainingPercent: 80, resetAt: fetchedAt),
                weekly: .init(remainingPercent: 30, resetAt: nil),
                models: [.init(id: "sonnet", name: "Sonnet", quota: .init(remainingPercent: 50, resetAt: nil))],
                extraUsage: .init(isEnabled: true, used: 1250, limit: 5000, currency: nil, utilization: 25),
                fetchedAt: fetchedAt
            )
        }))
        let value = try await provider.fetch().get()
        #expect(value.session == .init(remainingPercent: 80, resetAt: fetchedAt))
        #expect(value.weekly?.remainingPercent == 30)
        #expect(value.models == [.init(id: "sonnet", name: "Sonnet", quota: .init(remainingPercent: 50, resetAt: nil))])
        #expect(value.extraUsage == .init(isEnabled: true, used: 1250, limit: 5000, currency: nil, utilization: 25))
        #expect(value.fetchedAt == fetchedAt)
    }

    @Test(arguments: [
        (ClaudeUsageError.signedOut, RemoteProtocolError.Code.authenticationFailed),
        (.unauthorized, .authenticationFailed), (.permissionDenied, .authenticationFailed),
        (.network, .executionFailed), (.rateLimited, .executionFailed),
        (.invalidResponse, .invalidFrame), (.unsupported, .actionNotSupported)
    ])
    func mapsStableSanitizedErrors(input: (ClaudeUsageError, RemoteProtocolError.Code)) async {
        let provider = RemoteClaudeUsageProvider(usageClient: .init(fetch: { _ in throw input.0 }))
        guard case let .failure(error) = await provider.fetch() else {
            Issue.record("Expected a protocol failure")
            return
        }
        #expect(error.code == input.1)
    }
}
