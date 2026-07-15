import ComposableArchitecture
import Foundation

@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        let isSetupRequired: Bool
        var pairedMacs: IdentifiedArrayOf<PairedMac>
        var selectedMacID: UUID?
        @Presents var pairing: PairingFeature.State?

        init(
            isSetupRequired: Bool,
            pairedMacs: IdentifiedArrayOf<PairedMac> = [],
            selectedMacID: UUID? = nil
        ) {
            self.isSetupRequired = isSetupRequired
            self.pairedMacs = pairedMacs
            self.selectedMacID = selectedMacID
        }
    }

    enum Action: Equatable {
        case pairAnotherTapped
        case pairing(PresentationAction<PairingFeature.Action>)
        case foregroundChanged(Bool)
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case paired(PairedMac)
        case allMacsRemoved
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .pairAnotherTapped:
                state.pairing = PairingFeature.State()
                return .none

            case let .pairing(.presented(.delegate(.paired(mac)))):
                state.pairing = nil
                state.pairedMacs.updateOrAppend(mac)
                state.selectedMacID = mac.id
                return .send(.delegate(.paired(mac)))

            case .pairing(.presented(.delegate(.cancelled))):
                state.pairing = nil
                return .none

            case .pairing(.dismiss):
                return .none

            case let .foregroundChanged(isForegrounded):
                guard state.pairing != nil else { return .none }
                return .send(.pairing(.presented(.foregroundChanged(isForegrounded))))

            case .pairing, .delegate:
                return .none
            }
        }
        .ifLet(\.$pairing, action: \.pairing) {
            PairingFeature()
        }
    }
}
