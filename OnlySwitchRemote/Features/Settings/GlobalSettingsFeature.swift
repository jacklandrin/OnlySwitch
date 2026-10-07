import ComposableArchitecture
import Foundation

@Reducer
struct GlobalSettingsFeature {
    @ObservableState
    struct State: Equatable {
        let isSetupRequired: Bool
        var isKeepingScreenAwake: Bool
        var pairedMacs: IdentifiedArrayOf<PairedMac>
        var selectedMacID: UUID?
        var connectionStatuses: [UUID: MacConnectionStatus]
        @Presents var pairing: PairingFeature.State?
        @Presents var management: MacManagementFeature.State?

        init(
            isSetupRequired: Bool = false,
            isKeepingScreenAwake: Bool = RemoteIdleTimerClient.preferenceSeed(),
            pairedMacs: IdentifiedArrayOf<PairedMac> = [],
            selectedMacID: UUID? = nil,
            connectionStatuses: [UUID: MacConnectionStatus] = [:]
        ) {
            self.isSetupRequired = isSetupRequired
            self.isKeepingScreenAwake = isKeepingScreenAwake
            self.pairedMacs = pairedMacs
            self.selectedMacID = selectedMacID
            self.connectionStatuses = connectionStatuses
        }
    }

    enum Action: Equatable {
        case pairNewMacTapped
        case selectMac(UUID)
        case manageMac(UUID)
        case keepScreenAwakeToggled(Bool)
        case pairing(PresentationAction<PairingFeature.Action>)
        case management(PresentationAction<MacManagementFeature.Action>)
        case foregroundChanged(Bool)
        case delegate(Delegate)
    }

    @Dependency(\.remoteIdleTimer) var idleTimer

    enum Delegate: Equatable {
        case paired(PairedMac)
        case selectedMacChanged(PairedMac)
        case macForgotten(UUID)
        case allMacsRemoved
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .pairNewMacTapped:
                state.pairing = PairingFeature.State()
                return .none

            case let .selectMac(id):
                guard let mac = state.pairedMacs[id: id], id != state.selectedMacID else { return .none }
                state.selectedMacID = id
                return .send(.delegate(.selectedMacChanged(mac)))

            case let .manageMac(id):
                guard let mac = state.pairedMacs[id: id] else { return .none }
                let status = mac.requiresPairing ? .needsPairing : (state.connectionStatuses[id] ?? .unknown)
                state.management = .init(mac: mac, connectionStatus: status)
                return .none

            case let .keepScreenAwakeToggled(isEnabled):
                state.isKeepingScreenAwake = isEnabled
                return .run { _ in
                    await idleTimer.savePreference(isEnabled)
                }

            case let .pairing(.presented(.delegate(.paired(mac)))):
                state.pairing = nil
                state.pairedMacs.updateOrAppend(mac)
                state.selectedMacID = mac.id
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

            case let .management(.presented(.delegate(.rePair(id)))):
                guard state.pairedMacs[id: id] != nil else { return .none }
                state.management = nil
                state.pairing = PairingFeature.State()
                return .none

            case let .management(.presented(.delegate(.forgotten(id)))):
                state.management = nil
                let wasSelected = state.selectedMacID == id
                state.pairedMacs.remove(id: id)
                state.connectionStatuses[id] = nil
                if state.pairedMacs.isEmpty {
                    state.selectedMacID = nil
                    return .send(.delegate(.allMacsRemoved))
                }
                var effects: [Effect<Action>] = [.send(.delegate(.macForgotten(id)))]
                if wasSelected, let fallback = state.pairedMacs.first {
                    state.selectedMacID = fallback.id
                    effects.append(.send(.delegate(.selectedMacChanged(fallback))))
                }
                return .merge(effects)

            case .management(.dismiss):
                state.management = nil
                return .none

            case .pairing, .management, .delegate:
                return .none
            }
        }
        .ifLet(\.$pairing, action: \.pairing) { PairingFeature() }
        .ifLet(\.$management, action: \.management) { MacManagementFeature() }
    }
}
