import Dependencies
import DependenciesMacros
import Foundation
import StoreKit

struct RemoteSubscriptionProduct: Equatable, Sendable {
    let id: String
    let displayName: String
    let displayPrice: String
}

enum RemoteSubscriptionEntitlement: Equatable, Sendable {
    case inactive
    case active(expirationDate: Date?)
}

struct RemoteSubscriptionEntitlementCandidate: Equatable, Sendable {
    let productID: String
    let isVerified: Bool
    let expirationDate: Date?
    let revocationDate: Date?
    let isUpgraded: Bool
}

enum RemoteSubscriptionEntitlementPolicy {
    static func entitlement(
        for candidates: [RemoteSubscriptionEntitlementCandidate],
        now: Date
    ) -> RemoteSubscriptionEntitlement {
        let eligible = candidates.filter {
            $0.productID == RemoteSubscriptionClient.monthlyProductID
                && $0.isVerified
                && $0.revocationDate == nil
                && $0.isUpgraded == false
                && ($0.expirationDate.map { $0 > now } ?? true)
        }
        guard eligible.isEmpty == false else { return .inactive }
        if eligible.contains(where: { $0.expirationDate == nil }) {
            return .active(expirationDate: nil)
        }
        return .active(expirationDate: eligible.compactMap(\.expirationDate).max())
    }
}

@DependencyClient
struct RemoteSubscriptionClient: Sendable {
    static let monthlyProductID = "jacklandrin.onlyremote.plus.monthly"

    var loadProduct: @Sendable () async throws -> RemoteSubscriptionProduct?
    var currentEntitlement: @Sendable () async -> RemoteSubscriptionEntitlement = { .inactive }
    var restore: @Sendable () async throws -> RemoteSubscriptionEntitlement
}

extension RemoteSubscriptionClient: DependencyKey {
    static let liveValue = Self(
        loadProduct: {
            guard let product = try await Product.products(for: [monthlyProductID]).first(where: { product in
                guard product.id == monthlyProductID,
                      product.type == .autoRenewable,
                      let period = product.subscription?.subscriptionPeriod
                else { return false }
                return period.unit == .month && period.value == 1
            }) else { return nil }
            return .init(
                id: product.id,
                displayName: product.displayName,
                displayPrice: product.displayPrice
            )
        },
        currentEntitlement: { await liveEntitlement() },
        restore: {
            try await AppStore.sync()
            return await liveEntitlement()
        }
    )

    static let testValue = Self()

    private static func liveEntitlement() async -> RemoteSubscriptionEntitlement {
        var candidates: [RemoteSubscriptionEntitlementCandidate] = []
        for await result in Transaction.currentEntitlements {
            switch result {
            case let .verified(transaction):
                candidates.append(.init(
                    productID: transaction.productID,
                    isVerified: true,
                    expirationDate: transaction.expirationDate,
                    revocationDate: transaction.revocationDate,
                    isUpgraded: transaction.isUpgraded
                ))
            case let .unverified(transaction, _):
                candidates.append(.init(
                    productID: transaction.productID,
                    isVerified: false,
                    expirationDate: transaction.expirationDate,
                    revocationDate: transaction.revocationDate,
                    isUpgraded: transaction.isUpgraded
                ))
            }
        }
        return RemoteSubscriptionEntitlementPolicy.entitlement(for: candidates, now: .now)
    }
}

extension DependencyValues {
    var remoteSubscription: RemoteSubscriptionClient {
        get { self[RemoteSubscriptionClient.self] }
        set { self[RemoteSubscriptionClient.self] = newValue }
    }
}
