#if DEBUG
import ComposableArchitecture

@Reducer
struct RemoteDebugMenuFeature {
    @ObservableState
    struct State: Equatable {
        @Shared(.appStorage("onlyremoteDebugBypassPlusPaywall")) var bypassPlusPaywall = false
    }

    enum Action: Equatable {
        case bypassPaywallChanged(Bool)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .bypassPaywallChanged(enabled):
                state.$bypassPlusPaywall.withLock { $0 = enabled }
                return .none
            }
        }
    }
}
#endif
