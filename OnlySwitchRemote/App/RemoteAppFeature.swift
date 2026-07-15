import ComposableArchitecture
import Foundation

@Reducer
struct RemoteAppFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()
        var pairedMacs: IdentifiedArrayOf<PairedMac> = []
        var selectedMacID: UUID?
        var isLoading = false
        var loadGeneration: UInt64 = 0
        var isForegrounded = true
        var lifecycleGeneration: UInt64 = 0

        var requiresSetup: Bool {
            pairedMacs.isEmpty
        }
    }

    struct LaunchResponse: Equatable, Sendable {
        let pairedMacs: [PairedMac]
        let selectedMacID: UUID?
    }

    enum Action: Equatable {
        case task
        case launchResponse(UInt64, LaunchResponse)
        case settingsButtonTapped
        case scenePhaseChanged(Bool)
        case lifecycleResponse(UInt64)
        case path(StackActionOf<Path>)
    }

    @Reducer
    enum Path {
        case settings(SettingsFeature)
    }

    @Dependency(\.remoteConnection) var connection
    @Dependency(\.remotePersistence) var persistence

    private enum CancelID { case load, lifecycle }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.loadGeneration &+= 1
                state.isLoading = true
                let generation = state.loadGeneration
                return .run { [persistence] send in
                    let macs = (try? await persistence.loadPairedMacs()) ?? []
                    let selectedID = try? await persistence.loadSelectedMacID()
                    await send(.launchResponse(generation, .init(
                        pairedMacs: macs,
                        selectedMacID: selectedID
                    )))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .launchResponse(generation, response):
                guard generation == state.loadGeneration else { return .none }
                state.isLoading = false
                state.pairedMacs = IdentifiedArray(uniqueElements: response.pairedMacs)

                guard let selected = selectedMac(
                    from: response.pairedMacs,
                    persistedID: response.selectedMacID
                ) else {
                    state.selectedMacID = nil
                    state.path.removeAll()
                    state.path.append(.settings(.init(isSetupRequired: true)))
                    return .run { [connection] _ in await connection.select(nil) }
                }

                state.selectedMacID = selected.id
                if state.path.contains(where: Self.isRequiredSettings) {
                    state.path.removeAll()
                }
                return .run { [persistence, connection] _ in
                    if response.selectedMacID != selected.id {
                        try? await persistence.saveSelectedMacID(selected.id)
                    }
                    await connection.select(selected)
                }

            case .settingsButtonTapped:
                guard state.requiresSetup == false else { return .none }
                state.path.append(.settings(.init(
                    isSetupRequired: false,
                    pairedMacs: state.pairedMacs,
                    selectedMacID: state.selectedMacID
                )))
                return .none

            case let .scenePhaseChanged(isForegrounded):
                state.isForegrounded = isForegrounded
                state.lifecycleGeneration &+= 1
                let generation = state.lifecycleGeneration
                let settingsIDs = state.path.ids.filter { id in
                    if case .settings = state.path[id: id] { return true }
                    return false
                }
                var effects = settingsIDs.map { id in
                    Effect<Action>.send(.path(.element(
                        id: id,
                        action: .settings(.foregroundChanged(isForegrounded))
                    )))
                }
                effects.append(
                    .run { [connection] send in
                        await connection.setForegrounded(isForegrounded)
                        await send(.lifecycleResponse(generation))
                    }
                    .cancellable(id: CancelID.lifecycle, cancelInFlight: true)
                )
                return .merge(effects)

            case let .lifecycleResponse(generation):
                guard generation == state.lifecycleGeneration else { return .none }
                return .none

            case let .path(.popFrom(id)):
                guard case let .settings(settings)? = state.path[id: id], settings.isSetupRequired else {
                    return .none
                }
                return .none

            case let .path(.element(id, action: .settings(.delegate(.paired(mac))))):
                let wasRequired: Bool
                if case let .settings(settings)? = state.path[id: id] {
                    wasRequired = settings.isSetupRequired
                } else {
                    wasRequired = false
                }
                state.pairedMacs.updateOrAppend(mac)
                state.selectedMacID = mac.id
                if wasRequired { state.path.removeAll() }
                return .run { [persistence, connection] _ in
                    try? await persistence.saveSelectedMacID(mac.id)
                    await connection.select(mac)
                }

            case .path(.element(_, action: .settings(.delegate(.allMacsRemoved)))):
                state.pairedMacs.removeAll()
                state.selectedMacID = nil
                state.path.removeAll()
                state.path.append(.settings(.init(isSetupRequired: true)))
                return .run { [persistence, connection] _ in
                    try? await persistence.saveSelectedMacID(nil)
                    await connection.select(nil)
                }

            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
        Reduce { state, action in
            guard case .path(.popFrom) = action,
                  state.requiresSetup,
                  state.path.contains(where: Self.isRequiredSettings) == false
            else { return .none }
            state.path.append(.settings(.init(isSetupRequired: true)))
            return .none
        }
    }

    private func selectedMac(from macs: [PairedMac], persistedID: UUID?) -> PairedMac? {
        if let persistedID, let persisted = macs.first(where: { $0.id == persistedID }) {
            return persisted
        }
        return macs.first
    }

    private static func isRequiredSettings(_ state: Path.State) -> Bool {
        guard case let .settings(settings) = state else { return false }
        return settings.isSetupRequired
    }
}

extension RemoteAppFeature.Path.State: Equatable {}
extension RemoteAppFeature.Path.Action: Equatable {}
