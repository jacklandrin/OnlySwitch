import ComposableArchitecture

@Reducer
struct GlobalSettingsFeature {
    @ObservableState
    struct State: Equatable {
        let isSetupRequired: Bool
        @Presents var pairing: PairingFeature.State?

        init(isSetupRequired: Bool = false) {
            self.isSetupRequired = isSetupRequired
        }
    }

    enum Action: Equatable {
        case pairNewMacTapped
        case pairing(PresentationAction<PairingFeature.Action>)
        case foregroundChanged(Bool)
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case paired(PairedMac)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .pairNewMacTapped:
                state.pairing = PairingFeature.State()
                return .none

            case let .pairing(.presented(.delegate(.paired(mac)))):
                state.pairing = nil
                return .send(.delegate(.paired(mac)))

            case .pairing(.presented(.delegate(.cancelled))):
                state.pairing = nil
                return .none

            case .pairing(.dismiss):
                guard state.pairing?.isFinalizing != true else { return .none }
                state.pairing = nil
                return .none

            case let .foregroundChanged(isForegrounded):
                guard state.pairing != nil else { return .none }
                return .send(.pairing(.presented(.foregroundChanged(isForegrounded))))

            case .pairing, .delegate:
                return .none
            }
        }
        .ifLet(\.$pairing, action: \.pairing) { PairingFeature() }
    }
}
