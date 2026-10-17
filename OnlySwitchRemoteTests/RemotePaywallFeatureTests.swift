import ComposableArchitecture
import Foundation
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemotePaywallFeatureTests {
    private let product = RemoteSubscriptionProduct(
        id: RemoteSubscriptionClient.monthlyProductID,
        displayName: "OnlyRemote Plus", displayPrice: "€2.99"
    )

    @Test func productLoadingCannotEnablePurchases() async {
        let product = product
        let store = TestStore(initialState: RemotePaywallFeature.State()) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.loadProduct = { product }
            $0.remoteSubscription.currentEntitlement = { .inactive }
            $0.remoteSubscription.restore = { Issue.record("Loading must not restore purchases"); return .inactive }
        }
        await store.send(.task) { $0.isLoading = true }
        await store.receive(.productResponse(.success(product))) {
            $0.product = product
            $0.isLoading = false
        }
        await store.receive(.entitlementResponse(.inactive))
        #expect(store.state.canPurchase == false)
    }

    @Test func missingProductShowsUnavailable() async {
        let store = TestStore(initialState: RemotePaywallFeature.State()) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.loadProduct = { nil }
            $0.remoteSubscription.currentEntitlement = { .inactive }
        }
        await store.send(.task) { $0.isLoading = true }
        await store.receive(.productResponse(.success(nil))) {
            $0.isLoading = false
            $0.issue = .productUnavailable
        }
        await store.receive(.entitlementResponse(.inactive))
        #expect(store.state.product == nil)
        #expect(store.state.canPurchase == false)
    }

    @Test func failedLoadCanRetry() async {
        let product = product
        let attempts = LockIsolated(0)
        let store = TestStore(initialState: RemotePaywallFeature.State()) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.loadProduct = {
                let count = attempts.withValue { $0 += 1; return $0 }
                if count == 1 { throw PaywallTestError.failed }
                return product
            }
            $0.remoteSubscription.currentEntitlement = { .inactive }
        }
        await store.send(.task) { $0.isLoading = true }
        await store.receive(.productResponse(.failure)) {
            $0.isLoading = false
            $0.issue = .productLoadFailed
        }
        await store.receive(.entitlementResponse(.inactive))
        await store.send(.retryTapped) {
            $0.isLoading = true
            $0.issue = nil
        }
        await store.receive(.productResponse(.success(product))) {
            $0.isLoading = false
            $0.product = product
        }
        await store.receive(.entitlementResponse(.inactive))
        #expect(attempts.value == 2)
    }

    @Test func restorationIsExplicitAndIgnoresDuplicateTaps() async {
        let expiration = Date(timeIntervalSince1970: 2_000_000_000)
        let gate = RestoreGate()
        let store = TestStore(initialState: RemotePaywallFeature.State()) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.restore = { await gate.restore() }
        }
        await store.send(.restoreTapped) { $0.isRestoring = true }
        await gate.waitUntilEntered()
        await store.send(.restoreTapped)
        await gate.complete(.active(expirationDate: expiration))
        await store.receive(.restoreResponse(.success(.active(expirationDate: expiration)))) {
            $0.isRestoring = false
            $0.entitlement = .active(expirationDate: expiration)
            $0.restoreCompleted = true
        }
        #expect(await gate.calls == 1)
        #expect(store.state.canPurchase == false)
    }

    @Test func restoreWithoutEntitlementDoesNotGrantAccess() async {
        let store = TestStore(initialState: RemotePaywallFeature.State()) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.restore = { .inactive }
        }
        await store.send(.restoreTapped) { $0.isRestoring = true }
        await store.receive(.restoreResponse(.success(.inactive))) {
            $0.isRestoring = false
            $0.restoreCompleted = true
        }
        #expect(store.state.entitlement == .inactive)
        #expect(store.state.canPurchase == false)
    }

    @Test func restoreFailureCanRetry() async {
        let attempts = LockIsolated(0)
        let store = TestStore(initialState: RemotePaywallFeature.State()) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.restore = {
                let count = attempts.withValue { $0 += 1; return $0 }
                if count == 1 { throw PaywallTestError.failed }
                return .inactive
            }
        }
        await store.send(.restoreTapped) { $0.isRestoring = true }
        await store.receive(.restoreResponse(.failure)) {
            $0.isRestoring = false
            $0.issue = .restoreFailed
        }
        await store.send(.restoreTapped) {
            $0.isRestoring = true
            $0.issue = nil
        }
        await store.receive(.restoreResponse(.success(.inactive))) {
            $0.isRestoring = false
            $0.restoreCompleted = true
        }
        #expect(attempts.value == 2)
    }

    @Test func canceledEntitlementRefreshCannotOverwriteRestoredMembership() async {
        let product = product
        let staleRefresh = RestoreGate()
        let active = RemoteSubscriptionEntitlement.active(
            expirationDate: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let store = TestStore(initialState: RemotePaywallFeature.State()) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.loadProduct = { product }
            // Deliberately ignores cancellation, as a slow external API can do.
            $0.remoteSubscription.currentEntitlement = { await staleRefresh.restore() }
            $0.remoteSubscription.restore = { active }
        }
        await store.send(.task) { $0.isLoading = true }
        await store.receive(.productResponse(.success(product))) {
            $0.product = product
            $0.isLoading = false
        }
        await staleRefresh.waitUntilEntered()
        await store.send(.restoreTapped) { $0.isRestoring = true }
        await store.receive(.restoreResponse(.success(active))) {
            $0.isRestoring = false
            $0.entitlement = active
            $0.restoreCompleted = true
        }
        await staleRefresh.complete(.inactive)
        await store.finish()
        #expect(store.state.entitlement == active)
        #expect(store.state.restoreCompleted)
        #expect(store.state.canPurchase == false)
    }

    @Test func verifiedEntitlementStillCannotEnablePurchases() async {
        let active = RemoteSubscriptionEntitlement.active(expirationDate: nil)
        let store = TestStore(initialState: RemotePaywallFeature.State()) { RemotePaywallFeature() }
        await store.send(.entitlementResponse(active)) { $0.entitlement = active }
        #expect(store.state.canPurchase == false)
    }
}

private enum PaywallTestError: Error { case failed }

private actor RestoreGate {
    private(set) var calls = 0
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<RemoteSubscriptionEntitlement, Never>?

    func restore() async -> RemoteSubscriptionEntitlement {
        calls += 1
        return await withCheckedContinuation { continuation in
            completion = continuation
            enteredWaiters.forEach { $0.resume() }
            enteredWaiters.removeAll()
        }
    }

    func waitUntilEntered() async {
        guard calls == 0 else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func complete(_ result: RemoteSubscriptionEntitlement) {
        completion?.resume(returning: result)
        completion = nil
    }
}
