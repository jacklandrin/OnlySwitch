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

    @Test func productLoadingEnablesPurchases() async {
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
        await store.receive(.entitlementSnapshotResponse(0, .inactive))
        #expect(store.state.canPurchase)
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
        await store.receive(.entitlementSnapshotResponse(0, .inactive))
        #expect(store.state.product == nil)
        #expect(store.state.canPurchase == false)
    }

    @Test func reappearingPaywallRestartsCanceledProductLoad() async {
        let product = product
        let store = TestStore(initialState: RemotePaywallFeature.State(isLoading: true)) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.loadProduct = { product }
            $0.remoteSubscription.currentEntitlement = { .inactive }
        }
        await store.send(.task)
        await store.receive(.productResponse(.success(product))) {
            $0.isLoading = false
            $0.product = product
        }
        await store.receive(.entitlementSnapshotResponse(0, .inactive))
        #expect(store.state.canPurchase)
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
        await store.receive(.entitlementSnapshotResponse(0, .inactive))
        await store.send(.retryTapped) {
            $0.isLoading = true
            $0.issue = nil
        }
        await store.receive(.productResponse(.success(product))) {
            $0.isLoading = false
            $0.product = product
        }
        await store.receive(.entitlementSnapshotResponse(0, .inactive))
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

    @Test func purchaseSuccessGrantsMembership() async {
        var state = RemotePaywallFeature.State()
        state.product = product
        let active = RemoteSubscriptionEntitlement.active(expirationDate: nil)
        let store = TestStore(initialState: state) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.purchase = { .purchased(active) }
        }
        await store.send(.purchaseTapped) { $0.isPurchasing = true }
        await store.receive(.purchaseResponse(.success(.purchased(active)))) {
            $0.isPurchasing = false
            $0.entitlement = active
        }
        #expect(store.state.canPurchase == false)
    }

    @Test(arguments: [RemoteSubscriptionPurchaseResult.pending, .cancelled])
    func pendingAndCancellationDoNotGrantAccess(result: RemoteSubscriptionPurchaseResult) async {
        var state = RemotePaywallFeature.State()
        state.product = product
        let store = TestStore(initialState: state) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.purchase = { result }
        }
        await store.send(.purchaseTapped) { $0.isPurchasing = true }
        await store.receive(.purchaseResponse(.success(result))) {
            $0.isPurchasing = false
            $0.purchasePending = result == .pending
        }
        #expect(store.state.entitlement == .inactive)
        #expect(store.state.canPurchase)
    }

    @Test func verificationFailureCanRetryAndBusyOperationsAreIgnored() async {
        var state = RemotePaywallFeature.State()
        state.product = product
        let gate = RestoreGate()
        let store = TestStore(initialState: state) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.purchase = {
                _ = await gate.restore()
                throw RemoteSubscriptionPurchaseError.verificationFailed
            }
        }
        await store.send(.purchaseTapped) { $0.isPurchasing = true }
        await gate.waitUntilEntered()
        await store.send(.purchaseTapped)
        await store.send(.restoreTapped)
        await store.send(.retryTapped)
        await gate.complete(.inactive)
        await store.receive(.purchaseResponse(.failure(.verificationFailed))) {
            $0.isPurchasing = false
            $0.issue = .verificationFailed
        }
        #expect(await gate.calls == 1)
        #expect(store.state.canPurchase)
    }

    @Test func onlyVerifiedTargetTransactionsAreFinished() {
        #expect(RemoteSubscriptionEntitlementPolicy.shouldFinish(productID: RemoteSubscriptionClient.monthlyProductID, isVerified: true))
        #expect(RemoteSubscriptionEntitlementPolicy.shouldFinish(productID: RemoteSubscriptionClient.monthlyProductID, isVerified: false) == false)
        #expect(RemoteSubscriptionEntitlementPolicy.shouldFinish(productID: "unknown", isVerified: true) == false)
    }

    @Test func lateEntitlementRefreshCannotOverwritePurchasedMembership() async {
        let product = product
        let staleRefresh = RestoreGate()
        let active = RemoteSubscriptionEntitlement.active(expirationDate: nil)
        let store = TestStore(initialState: RemotePaywallFeature.State()) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.loadProduct = { product }
            $0.remoteSubscription.currentEntitlement = { await staleRefresh.restore() }
            $0.remoteSubscription.purchase = { .purchased(active) }
        }
        await store.send(.task) { $0.isLoading = true }
        await store.receive(.productResponse(.success(product))) {
            $0.product = product
            $0.isLoading = false
        }
        await staleRefresh.waitUntilEntered()
        await store.send(.purchaseTapped) { $0.isPurchasing = true }
        await store.receive(.purchaseResponse(.success(.purchased(active)))) {
            $0.isPurchasing = false
            $0.entitlement = active
        }
        await staleRefresh.complete(.inactive)
        await store.finish()
        #expect(store.state.entitlement == active)
    }

    @Test func authoritativeApprovalInvalidatesStaleSheetRefresh() async {
        let product = product
        let staleRefresh = RestoreGate()
        let active = RemoteSubscriptionEntitlement.active(expirationDate: nil)
        let store = TestStore(initialState: RemotePaywallFeature.State()) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.loadProduct = { product }
            $0.remoteSubscription.currentEntitlement = { await staleRefresh.restore() }
        }
        await store.send(.task) { $0.isLoading = true }
        await store.receive(.productResponse(.success(product))) {
            $0.product = product
            $0.isLoading = false
        }
        await staleRefresh.waitUntilEntered()
        await store.send(.authoritativeEntitlementUpdated(active)) {
            $0.entitlement = active
            $0.entitlementGeneration = 1
        }
        await staleRefresh.complete(.inactive)
        await store.receive(.entitlementSnapshotResponse(0, .inactive))
        await store.finish()
        #expect(store.state.entitlement == active)
        #expect(store.state.canPurchase == false)
    }

    @Test func authoritativeInactiveDoesNotCancelProductLoading() async {
        let product = product
        let productGate = RestoreGate()
        let store = TestStore(initialState: RemotePaywallFeature.State()) { RemotePaywallFeature() } withDependencies: {
            $0.remoteSubscription.loadProduct = {
                _ = await productGate.restore()
                return product
            }
            $0.remoteSubscription.currentEntitlement = { .inactive }
        }
        await store.send(.task) { $0.isLoading = true }
        await productGate.waitUntilEntered()
        await store.send(.authoritativeEntitlementUpdated(.inactive)) { $0.entitlementGeneration = 1 }
        #expect(store.state.isLoading)
        await productGate.complete(.inactive)
        await store.receive(.productResponse(.success(product))) {
            $0.isLoading = false
            $0.product = product
        }
        await store.receive(.entitlementSnapshotResponse(0, .inactive))
        #expect(store.state.canPurchase)
    }

    @Test func expiredUpdateDoesNotOverrideAnotherValidRenewal() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let candidates = [
            RemoteSubscriptionEntitlementCandidate(productID: RemoteSubscriptionClient.monthlyProductID, isVerified: true,
                expirationDate: now.addingTimeInterval(-60), revocationDate: nil, isUpgraded: false),
            RemoteSubscriptionEntitlementCandidate(productID: RemoteSubscriptionClient.monthlyProductID, isVerified: true,
                expirationDate: now.addingTimeInterval(3600), revocationDate: nil, isUpgraded: false)
        ]
        #expect(RemoteSubscriptionEntitlementPolicy.entitlement(for: candidates, now: now) == .active(expirationDate: now.addingTimeInterval(3600)))
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

@MainActor
struct RemoteAphroditeAccessFeatureTests {
    @Test func inactiveUsersSeePaywallByDefault() {
        #expect(RemoteAphroditeAccessFeature.State().canAccess == false)
    }

    @Test func membershipRefreshDoesNotLoadProducts() async {
        let store = TestStore(initialState: RemoteAphroditeAccessFeature.State()) {
            RemoteAphroditeAccessFeature()
        } withDependencies: {
            $0.remoteSubscription.currentEntitlement = { .active(expirationDate: nil) }
            $0.remoteSubscription.loadProduct = { Issue.record("Access must not wait for product loading"); return nil }
        }
        await store.send(.refresh) { $0.refreshGeneration = 1 }
        await store.receive(.entitlementResponse(1, .active(expirationDate: nil))) {
            $0.entitlement = .active(expirationDate: nil)
            $0.paywall.entitlement = .active(expirationDate: nil)
        }
        #expect(store.state.canAccess)
    }

    @Test func transactionUpdatesRefreshAccessAndRejectStaleResponse() async {
        let (stream, continuation) = AsyncStream<RemoteSubscriptionEntitlement>.makeStream()
        let store = TestStore(initialState: RemoteAphroditeAccessFeature.State()) { RemoteAphroditeAccessFeature() } withDependencies: {
            $0.remoteSubscription.currentEntitlement = { .inactive }
            $0.remoteSubscription.entitlementUpdates = { stream }
        }
        await store.send(.task)
        await store.receive(.refresh) { $0.refreshGeneration = 1 }
        await store.receive(.entitlementResponse(1, .inactive))
        continuation.yield(.active(expirationDate: nil))
        await store.receive(.entitlementUpdated(.active(expirationDate: nil))) {
            $0.refreshGeneration = 2
            $0.entitlement = .active(expirationDate: nil)
            $0.paywall.entitlement = .active(expirationDate: nil)
        }
        continuation.yield(.inactive)
        await store.receive(.entitlementUpdated(.inactive)) {
            $0.refreshGeneration = 3
            $0.entitlement = .inactive
            $0.paywall.entitlement = .inactive
        }
        await store.send(.entitlementResponse(1, .active(expirationDate: nil)))
        #expect(store.state.canAccess == false)
        continuation.finish()
        await store.finish()
    }

    @Test func revokedMembershipLocksAccess() async {
        var state = RemoteAphroditeAccessFeature.State()
        state.entitlement = .active(expirationDate: nil)
        let store = TestStore(initialState: state) { RemoteAphroditeAccessFeature() }
        await store.send(.entitlementUpdated(.inactive)) {
            $0.entitlement = .inactive
            $0.refreshGeneration = 1
        }
        #expect(store.state.canAccess == false)
    }

    @Test func restoreUnlocksEmbeddedPaywallAndInvalidatesOldRefresh() async {
        let store = TestStore(initialState: RemoteAphroditeAccessFeature.State()) { RemoteAphroditeAccessFeature() }
        await store.send(.paywall(.restoreResponse(.success(.active(expirationDate: nil))))) {
            $0.paywall.entitlement = .active(expirationDate: nil)
            $0.paywall.restoreCompleted = true
            $0.entitlement = .active(expirationDate: nil)
            $0.refreshGeneration = 1
        }
        await store.send(.entitlementResponse(0, .inactive))
        #expect(store.state.canAccess)
        #expect(store.state.paywall.canPurchase == false)
    }

    @Test func purchaseUnlocksEmbeddedPaywallAndInvalidatesOldRefresh() async {
        let store = TestStore(initialState: RemoteAphroditeAccessFeature.State()) { RemoteAphroditeAccessFeature() }
        await store.send(.paywall(.purchaseResponse(.success(.purchased(.active(expirationDate: nil)))))) {
            $0.paywall.entitlement = .active(expirationDate: nil)
            $0.entitlement = .active(expirationDate: nil)
            $0.refreshGeneration = 1
        }
        await store.send(.entitlementResponse(0, .inactive))
        #expect(store.state.canAccess)
    }

    @Test func membershipExpirationLocksWithoutTabSwitch() async {
        let clock = TestClock()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = TestStore(initialState: RemoteAphroditeAccessFeature.State()) { RemoteAphroditeAccessFeature() } withDependencies: {
            $0.continuousClock = clock
            $0.date.now = now
        }
        await store.send(.entitlementUpdated(.active(expirationDate: now.addingTimeInterval(60)))) {
            $0.refreshGeneration = 1
            $0.entitlement = .active(expirationDate: now.addingTimeInterval(60))
            $0.paywall.entitlement = .active(expirationDate: now.addingTimeInterval(60))
        }
        #expect(store.state.canAccess)
        await clock.advance(by: .seconds(60))
        await store.receive(.entitlementExpired(now.addingTimeInterval(60))) {
            $0.entitlement = .inactive
            $0.paywall.entitlement = .inactive
        }
        #expect(store.state.canAccess == false)
    }

    @Test func expirationStillLocksDuringSlowRefresh() async {
        let clock = TestClock()
        let gate = RestoreGate()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = TestStore(initialState: RemoteAphroditeAccessFeature.State()) { RemoteAphroditeAccessFeature() } withDependencies: {
            $0.continuousClock = clock
            $0.date.now = now
            $0.remoteSubscription.currentEntitlement = { await gate.restore() }
        }
        let expiration = now.addingTimeInterval(60)
        await store.send(.entitlementUpdated(.active(expirationDate: expiration))) {
            $0.refreshGeneration = 1
            $0.entitlement = .active(expirationDate: expiration)
            $0.paywall.entitlement = .active(expirationDate: expiration)
        }
        await store.send(.refresh) { $0.refreshGeneration = 2 }
        await gate.waitUntilEntered()
        await clock.advance(by: .seconds(60))
        await store.receive(.entitlementExpired(expiration)) {
            $0.entitlement = .inactive
            $0.paywall.entitlement = .inactive
        }
        #expect(store.state.canAccess == false)
        await gate.complete(.inactive)
        await store.receive(.entitlementResponse(2, .inactive))
    }

    #if DEBUG
    @Test func bypassCanBeDisabledWithoutLosingMembershipState() async {
        let store = TestStore(initialState: RemoteAphroditeAccessFeature.State()) { RemoteAphroditeAccessFeature() }
        let debug = TestStore(initialState: RemoteDebugMenuFeature.State()) { RemoteDebugMenuFeature() }
        await debug.send(.bypassPaywallChanged(true)) { $0.$bypassAphroditePaywall.withLock { $0 = true } }
        #expect(store.state.canAccess)
        await debug.send(.bypassPaywallChanged(false)) { $0.$bypassAphroditePaywall.withLock { $0 = false } }
        #expect(store.state.canAccess == false)
        #expect(store.state.entitlement == .inactive)
    }
    #endif
}
