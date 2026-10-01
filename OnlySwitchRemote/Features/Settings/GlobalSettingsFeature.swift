import ComposableArchitecture

@Reducer
struct GlobalSettingsFeature {
    @ObservableState
    struct State: Equatable {
        let isSetupRequired: Bool
        var isKeepingScreenAwake: Bool
        @Presents var pairing: PairingFeature.State?

        init(
            isSetupRequired: Bool = false,
            isKeepingScreenAwake: Bool = RemoteIdleTimerClient.preferenceSeed()
        ) {
            self.isSetupRequired = isSetupRequired
            self.isKeepingScreenAwake = isKeepingScreenAwake
        }
    }

    enum Action: Equatable {
        case pairNewMacTapped
        case keepScreenAwakeToggled(Bool)
        case pairing(PresentationAction<PairingFeature.Action>)
        case foregroundChanged(Bool)
        case delegate(Delegate)
    }

    @Dependency(\.remoteIdleTimer) var idleTimer

    enum Delegate: Equatable {
        case paired(PairedMac)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .pairNewMacTapped:
                state.pairing = PairingFeature.State()
                return .none

            case let .keepScreenAwakeToggled(isEnabled):
                state.isKeepingScreenAwake = isEnabled
                return .run { _ in
                    await idleTimer.savePreference(isEnabled)
                }

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
