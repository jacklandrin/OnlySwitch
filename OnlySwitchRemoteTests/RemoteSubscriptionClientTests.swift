import Foundation
import Testing
@testable import OnlySwitchRemote

struct RemoteSubscriptionClientTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func verifiedCurrentMonthlySubscriptionGrantsEntitlement() {
        let expiration = now.addingTimeInterval(300)
        #expect(RemoteSubscriptionEntitlementPolicy.entitlement(for: [candidate(expiration: expiration)], now: now) == .active(expirationDate: expiration))
    }

    @Test(arguments: ["expired", "boundary", "revoked", "unverified", "unrelated", "upgraded"])
    func invalidTransactionCannotGrantEntitlement(reason: String) {
        let value = RemoteSubscriptionEntitlementCandidate(
            productID: reason == "unrelated" ? "another.product" : RemoteSubscriptionClient.monthlyProductID,
            isVerified: reason != "unverified",
            expirationDate: now.addingTimeInterval(reason == "expired" ? -1 : reason == "boundary" ? 0 : 300),
            revocationDate: reason == "revoked" ? now : nil,
            isUpgraded: reason == "upgraded"
        )
        #expect(RemoteSubscriptionEntitlementPolicy.entitlement(for: [value], now: now) == .inactive)
    }

    @Test func noTransactionsIsInactive() {
        #expect(RemoteSubscriptionEntitlementPolicy.entitlement(for: [], now: now) == .inactive)
    }

    @Test func validCurrentEntitlementWithoutExpirationIsAccepted() {
        #expect(RemoteSubscriptionEntitlementPolicy.entitlement(for: [candidate(expiration: nil)], now: now) == .active(expirationDate: nil))
    }

    @Test func selectsLatestValidExpirationRegardlessOfSequence() {
        let earlier = candidate(expiration: now.addingTimeInterval(100))
        let later = candidate(expiration: now.addingTimeInterval(300))
        let expired = candidate(expiration: now.addingTimeInterval(-1))
        for values in [[earlier, later, expired], [later, expired, earlier]] {
            #expect(RemoteSubscriptionEntitlementPolicy.entitlement(for: values, now: now) == .active(expirationDate: later.expirationDate))
        }
    }

    private func candidate(expiration: Date?) -> RemoteSubscriptionEntitlementCandidate {
        .init(productID: RemoteSubscriptionClient.monthlyProductID, isVerified: true, expirationDate: expiration, revocationDate: nil, isUpgraded: false)
    }
}
