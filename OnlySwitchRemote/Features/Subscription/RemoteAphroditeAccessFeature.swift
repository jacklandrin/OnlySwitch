import ComposableArchitecture
import Foundation

@Reducer
struct RemoteAphroditeAccessFeature {
    @ObservableState
    struct State: Equatable {
        var entitlement: RemoteSubscriptionEntitlement = .inactive
        var paywall = RemotePaywallFeature.State()
        var refreshGeneration: UInt64 = 0
        #if DEBUG
        @Shared(.appStorage("onlyremoteDebugBypassAphroditePaywall")) var bypassAphroditePaywall = false
        #endif

        var canAccess: Bool {
            #if DEBUG
            if bypassAphroditePaywall { return true }
            #endif
            if case .active = entitlement { return true }
            return false
        }
    }

    enum Action: Equatable {
        case task
        case refresh
        case entitlementResponse(UInt64, RemoteSubscriptionEntitlement)
        case entitlementUpdated(RemoteSubscriptionEntitlement)
        case entitlementExpired(Date)
        case paywall(RemotePaywallFeature.Action)
    }

    @Dependency(\.remoteSubscription) var subscription
    @Dependency(\.date.now) var now
    @Dependency(\.continuousClock) var clock
    private enum CancelID { case refresh, updates, expiration }

    var body: some ReducerOf<Self> {
        Scope(state: \.paywall, action: \.paywall) { RemotePaywallFeature() }
        Reduce { state, action in
            switch action {
            case .task:
                return .merge(
                    .send(.refresh),
                    .run { [subscription] send in
                        for await entitlement in subscription.entitlementUpdates() {
                            guard Task.isCancelled == false else { return }
                            await send(.entitlementUpdated(entitlement))
                        }
                    }.cancellable(id: CancelID.updates, cancelInFlight: true)
                )

            case .refresh:
                state.refreshGeneration &+= 1
                let generation = state.refreshGeneration
                return .run { [subscription] send in
                    let entitlement = await subscription.currentEntitlement()
                    guard Task.isCancelled == false else { return }
                    await send(.entitlementResponse(generation, entitlement))
                }.cancellable(id: CancelID.refresh, cancelInFlight: true)

            case let .entitlementResponse(generation, entitlement):
                guard generation == state.refreshGeneration else { return .none }
                return update(entitlement, state: &state)

            case let .entitlementUpdated(entitlement),
                 let .paywall(.purchaseResponse(.success(.purchased(entitlement)))),
                 let .paywall(.restoreResponse(.success(entitlement))):
                state.refreshGeneration &+= 1
                return .merge(.cancel(id: CancelID.refresh), update(entitlement, state: &state))

            case let .entitlementExpired(expirationDate):
                guard state.entitlement == .active(expirationDate: expirationDate) else { return .none }
                state.entitlement = .inactive
                state.paywall.entitlement = .inactive
                return .none

            case .paywall:
                return .none
            }
        }
    }

    private func update(_ entitlement: RemoteSubscriptionEntitlement, state: inout State) -> Effect<Action> {
        guard case let .active(expirationDate) = entitlement else {
            state.entitlement = .inactive
            state.paywall.entitlement = .inactive
            return .cancel(id: CancelID.expiration)
        }
        guard let expirationDate else {
            state.entitlement = entitlement
            state.paywall.entitlement = entitlement
            state.paywall.purchasePending = false
            return .cancel(id: CancelID.expiration)
        }
        let delay = expirationDate.timeIntervalSince(now)
        guard delay > 0 else {
            state.entitlement = .inactive
            state.paywall.entitlement = .inactive
            return .cancel(id: CancelID.expiration)
        }
        state.entitlement = entitlement
        state.paywall.entitlement = entitlement
        state.paywall.purchasePending = false
        return .run { [clock] send in
            try await clock.sleep(for: .seconds(delay))
            await send(.entitlementExpired(expirationDate))
        }.cancellable(id: CancelID.expiration, cancelInFlight: true)
    }
}
