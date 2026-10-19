import ComposableArchitecture
import Foundation

@Reducer
struct RemotePaywallFeature {
    @ObservableState
    struct State: Equatable {
        var product: RemoteSubscriptionProduct?
        var isLoading = false
        var isRestoring = false
        var isPurchasing = false
        var purchasePending = false
        var entitlementGeneration: UInt64 = 0
        var entitlement: RemoteSubscriptionEntitlement = .inactive
        var issue: Issue?
        var restoreCompleted = false

        var isBusy: Bool { isLoading || isRestoring || isPurchasing }
        var canPurchase: Bool { product != nil && isBusy == false && entitlement == .inactive }
    }

    enum Action: Equatable {
        case task
        case retryTapped
        case productResponse(ProductResult)
        case entitlementResponse(RemoteSubscriptionEntitlement)
        case entitlementSnapshotResponse(UInt64, RemoteSubscriptionEntitlement)
        case authoritativeEntitlementUpdated(RemoteSubscriptionEntitlement)
        case restoreTapped
        case restoreResponse(RestoreResult)
        case purchaseTapped
        case purchaseResponse(PurchaseResult)
    }

    enum ProductResult: Equatable, Sendable {
        case success(RemoteSubscriptionProduct?)
        case failure
    }

    enum RestoreResult: Equatable, Sendable {
        case success(RemoteSubscriptionEntitlement)
        case failure
    }

    enum PurchaseResult: Equatable, Sendable {
        case success(RemoteSubscriptionPurchaseResult)
        case failure(RemoteSubscriptionPurchaseError)
    }

    enum Issue: Equatable, Sendable {
        case productUnavailable
        case productLoadFailed
        case restoreFailed
        case purchaseFailed
        case verificationFailed
    }

    @Dependency(\.remoteSubscription) var subscription
    private enum CancelID { case load, restore }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task, .retryTapped:
                guard state.isPurchasing == false, state.isRestoring == false else { return .none }
                if case .retryTapped = action, state.isLoading { return .none }
                state.isLoading = true
                state.issue = nil
                state.restoreCompleted = false
                let generation = state.entitlementGeneration
                return .concatenate(
                    .run { [subscription] send in
                        do {
                            let product = try await subscription.loadProduct()
                            guard Task.isCancelled == false else { return }
                            await send(.productResponse(.success(product)))
                        } catch is CancellationError {
                            return
                        } catch {
                            guard Task.isCancelled == false else { return }
                            await send(.productResponse(.failure))
                        }
                    },
                    .run { [subscription] send in
                        let entitlement = await subscription.currentEntitlement()
                        guard Task.isCancelled == false else { return }
                        await send(.entitlementSnapshotResponse(generation, entitlement))
                    }
                )
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .productResponse(.success(product)):
                state.isLoading = false
                state.product = product
                state.issue = product == nil ? .productUnavailable : nil
                return .none

            case .productResponse(.failure):
                state.isLoading = false
                state.product = nil
                state.issue = .productLoadFailed
                return .none

            case let .entitlementResponse(entitlement):
                state.entitlement = entitlement
                return .none

            case let .entitlementSnapshotResponse(generation, entitlement):
                guard generation == state.entitlementGeneration else { return .none }
                state.entitlement = entitlement
                return .none

            case let .authoritativeEntitlementUpdated(entitlement):
                state.entitlementGeneration &+= 1
                state.entitlement = entitlement
                if case .active = entitlement {
                    state.purchasePending = false
                    state.issue = nil
                }
                return .none

            case .restoreTapped:
                guard state.isBusy == false else { return .none }
                state.isRestoring = true
                state.issue = nil
                state.restoreCompleted = false
                return .concatenate(
                    .cancel(id: CancelID.load),
                    .run { [subscription] send in
                        do {
                            await send(.restoreResponse(.success(try await subscription.restore())))
                        } catch is CancellationError {
                            return
                        } catch {
                            await send(.restoreResponse(.failure))
                        }
                    }
                    .cancellable(id: CancelID.restore, cancelInFlight: true)
                )

            case let .restoreResponse(.success(entitlement)):
                state.isRestoring = false
                state.entitlement = entitlement
                state.restoreCompleted = true
                return .none

            case .restoreResponse(.failure):
                state.isRestoring = false
                state.issue = .restoreFailed
                return .none

            case .purchaseTapped:
                guard state.canPurchase else { return .none }
                state.isPurchasing = true
                state.purchasePending = false
                state.issue = nil
                state.restoreCompleted = false
                return .concatenate(
                    .cancel(id: CancelID.load),
                    .run { [subscription] send in
                        do {
                            await send(.purchaseResponse(.success(try await subscription.purchase())))
                        } catch is CancellationError {
                            await send(.purchaseResponse(.success(.cancelled)))
                        } catch let error as RemoteSubscriptionPurchaseError {
                            await send(.purchaseResponse(.failure(error)))
                        } catch {
                            await send(.purchaseResponse(.failure(.purchaseFailed)))
                        }
                    }
                )

            case let .purchaseResponse(.success(result)):
                state.isPurchasing = false
                state.purchasePending = result == .pending
                if case let .purchased(entitlement) = result { state.entitlement = entitlement }
                return .none

            case let .purchaseResponse(.failure(error)):
                state.isPurchasing = false
                state.issue = error == .verificationFailed ? .verificationFailed :
                    error == .productUnavailable ? .productUnavailable : .purchaseFailed
                return .none
            }
        }
    }
}
