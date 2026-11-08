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
    static func shouldFinish(productID: String, isVerified: Bool) -> Bool {
        productID == RemoteSubscriptionClient.monthlyProductID && isVerified
    }

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

enum RemoteSubscriptionPurchaseResult: Equatable, Sendable {
    case purchased(RemoteSubscriptionEntitlement)
    case pending
    case cancelled
}

enum RemoteSubscriptionPurchaseError: Error, Equatable, Sendable {
    case productUnavailable
    case verificationFailed
    case purchaseFailed
    case operationInProgress
}

@DependencyClient
struct RemoteSubscriptionClient: Sendable {
    static let monthlyProductID = "jacklandrin.onlyremote.plus.monthly"

    var loadProduct: @Sendable () async throws -> RemoteSubscriptionProduct?
    var currentEntitlement: @Sendable () async -> RemoteSubscriptionEntitlement = { .inactive }
    var entitlementUpdates: @Sendable () -> AsyncStream<RemoteSubscriptionEntitlement> = { .finished }
    var restore: @Sendable () async throws -> RemoteSubscriptionEntitlement
    var purchase: @Sendable () async throws -> RemoteSubscriptionPurchaseResult
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
        entitlementUpdates: {
            let (stream, continuation) = AsyncStream<RemoteSubscriptionEntitlement>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let task = Task {
                let id = await RemoteSubscriptionStore.shared.add(continuation)
                for await result in Transaction.updates {
                    guard Task.isCancelled == false else { break }
                    guard case let .verified(transaction) = result,
                          RemoteSubscriptionEntitlementPolicy.shouldFinish(productID: transaction.productID, isVerified: true)
                    else { continue }
                    await RemoteSubscriptionStore.shared.handleUpdate(transaction)
                    await transaction.finish()
                }
                await RemoteSubscriptionStore.shared.remove(id)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
            return stream
        },
        restore: { try await RemoteSubscriptionStore.shared.restore() },
        purchase: { try await RemoteSubscriptionStore.shared.purchase() }
    )

    static let testValue = Self()

    fileprivate static func transactionEntitlement(_ transaction: Transaction) -> RemoteSubscriptionEntitlement {
        RemoteSubscriptionEntitlementPolicy.entitlement(for: [.init(
            productID: transaction.productID,
            isVerified: true,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded
        )], now: .now)
    }

    fileprivate static func liveEntitlement(updatedTransaction: Transaction? = nil) async -> RemoteSubscriptionEntitlement {
        var candidates: [RemoteSubscriptionEntitlementCandidate] = []
        if let transaction = updatedTransaction {
            candidates.append(.init(
                productID: transaction.productID,
                isVerified: true,
                expirationDate: transaction.expirationDate,
                revocationDate: transaction.revocationDate,
                isUpgraded: transaction.isUpgraded
            ))
        }
        for await result in Transaction.currentEntitlements {
            switch result {
            case let .verified(transaction):
                guard transaction.id != updatedTransaction?.id else { continue }
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

/// Owns purchase lifetime independently of a presented paywall and serializes mutations
/// across the inline and Settings presentations.
private actor RemoteSubscriptionStore {
    static let shared = RemoteSubscriptionStore()
    private var isMutating = false
    private var publicationRevision: UInt64 = 0
    private var subscribers: [UUID: AsyncStream<RemoteSubscriptionEntitlement>.Continuation] = [:]

    func add(_ continuation: AsyncStream<RemoteSubscriptionEntitlement>.Continuation) -> UUID {
        let id = UUID()
        subscribers[id] = continuation
        return id
    }

    func remove(_ id: UUID) { subscribers[id] = nil }

    func publish(_ entitlement: RemoteSubscriptionEntitlement) {
        publicationRevision &+= 1
        for subscriber in subscribers.values { subscriber.yield(entitlement) }
    }

    func handleUpdate(_ transaction: Transaction) async {
        // A slow enumeration must not overwrite a purchase / restore delivered meanwhile.
        // Retry the authoritative snapshot rather than dropping a revocation update.
        while Task.isCancelled == false {
            let revision = publicationRevision
            let entitlement = await RemoteSubscriptionClient.liveEntitlement(updatedTransaction: transaction)
            guard Task.isCancelled == false else { return }
            guard revision == publicationRevision else { continue }
            publish(entitlement)
            return
        }
    }

    func purchase() async throws -> RemoteSubscriptionPurchaseResult {
        guard isMutating == false else { throw RemoteSubscriptionPurchaseError.operationInProgress }
        isMutating = true
        defer { isMutating = false }
        // An unstructured task intentionally survives view / sheet task cancellation.
        let operation = Task { () throws -> RemoteSubscriptionPurchaseResult in
            guard let product = try await Product.products(for: [RemoteSubscriptionClient.monthlyProductID]).first(where: {
                $0.id == RemoteSubscriptionClient.monthlyProductID && $0.type == .autoRenewable &&
                    $0.subscription?.subscriptionPeriod.unit == .month && $0.subscription?.subscriptionPeriod.value == 1
            }) else { throw RemoteSubscriptionPurchaseError.productUnavailable }
            switch try await product.purchase() {
            case let .success(result):
                guard case let .verified(transaction) = result,
                      RemoteSubscriptionEntitlementPolicy.shouldFinish(productID: transaction.productID, isVerified: true)
                else { throw RemoteSubscriptionPurchaseError.verificationFailed }
                let entitlement = RemoteSubscriptionClient.transactionEntitlement(transaction)
                guard case .active = entitlement else {
                    await transaction.finish()
                    throw RemoteSubscriptionPurchaseError.verificationFailed
                }
                publish(entitlement)
                await transaction.finish()
                return .purchased(entitlement)
            case .pending: return .pending
            case .userCancelled: return .cancelled
            @unknown default: throw RemoteSubscriptionPurchaseError.purchaseFailed
            }
        }
        let result = try await operation.value
        return result
    }

    func restore() async throws -> RemoteSubscriptionEntitlement {
        guard isMutating == false else { throw RemoteSubscriptionPurchaseError.operationInProgress }
        isMutating = true
        defer { isMutating = false }
        let operation = Task {
            try await AppStore.sync()
            return await RemoteSubscriptionClient.liveEntitlement()
        }
        let entitlement = try await operation.value
        publish(entitlement)
        return entitlement
    }
}

extension DependencyValues {
    var remoteSubscription: RemoteSubscriptionClient {
        get { self[RemoteSubscriptionClient.self] }
        set { self[RemoteSubscriptionClient.self] = newValue }
    }
}
