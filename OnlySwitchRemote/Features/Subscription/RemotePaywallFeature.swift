import ComposableArchitecture
import Foundation

@Reducer
struct RemotePaywallFeature {
    @ObservableState
    struct State: Equatable {
        var product: RemoteSubscriptionProduct?
        var isLoading = false
        var isRestoring = false
        var entitlement: RemoteSubscriptionEntitlement = .inactive
        var issue: Issue?
        var restoreCompleted = false

        var canPurchase: Bool { false }
    }

    enum Action: Equatable {
        case task
        case retryTapped
        case productResponse(ProductResult)
        case entitlementResponse(RemoteSubscriptionEntitlement)
        case restoreTapped
        case restoreResponse(RestoreResult)
    }

    enum ProductResult: Equatable, Sendable {
        case success(RemoteSubscriptionProduct?)
        case failure
    }

    enum RestoreResult: Equatable, Sendable {
        case success(RemoteSubscriptionEntitlement)
        case failure
    }

    enum Issue: Equatable, Sendable {
        case productUnavailable
        case productLoadFailed
        case restoreFailed
    }

    @Dependency(\.remoteSubscription) var subscription
    private enum CancelID { case load, restore }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task, .retryTapped:
                guard state.isLoading == false, state.isRestoring == false else { return .none }
                state.isLoading = true
                state.issue = nil
                state.restoreCompleted = false
                return .concatenate(
                    .run { [subscription] send in
                        do {
                            await send(.productResponse(.success(try await subscription.loadProduct())))
                        } catch is CancellationError {
                            return
                        } catch {
                            await send(.productResponse(.failure))
                        }
                    },
                    .run { [subscription] send in
                        let entitlement = await subscription.currentEntitlement()
                        guard Task.isCancelled == false else { return }
                        await send(.entitlementResponse(entitlement))
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

            case .restoreTapped:
                guard state.isRestoring == false, state.isLoading == false else { return .none }
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
            }
        }
    }
}
