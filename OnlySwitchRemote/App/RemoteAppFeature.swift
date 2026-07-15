import ComposableArchitecture
import Foundation

@Reducer
struct RemoteAppFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()
        var requiredSettings: SettingsFeature.State?
        var pairedMacs: IdentifiedArrayOf<PairedMac> = []
        var selectedMacID: UUID?
        var hasCompletedInitialSetup: Bool
        var isLoading = false
        var loadGeneration: UInt64 = 0
        var isForegrounded = true
        var lifecycleGeneration: UInt64 = 0
        let persistenceWriterID: UUID
        var nextPersistenceSequence: UInt64 = 0
        var pendingPersistenceIntent: RemoteAppPersistenceIntent?
        var isPersisting = false
        var rootIssue: RootIssue?

        init(
            hasCompletedInitialSetup: Bool,
            persistenceWriterID: UUID = UUID()
        ) {
            self.hasCompletedInitialSetup = hasCompletedInitialSetup
            self.persistenceWriterID = persistenceWriterID
            if hasCompletedInitialSetup == false {
                requiredSettings = .init(isSetupRequired: true)
            }
        }

        var requiresSetup: Bool { requiredSettings != nil }
    }

    struct LaunchResponse: Equatable, Sendable {
        let pairedMacs: [PairedMac]
        let selectedMacID: UUID?
    }

    enum LaunchResult: Equatable, Sendable {
        case success(LaunchResponse)
        case failure
    }

    enum PersistenceResult: Equatable, Sendable {
        case success
        case failure
    }

    enum RootIssue: Equatable, Sendable {
        case loadFailed
        case persistenceFailed

        var title: LocalizedStringResource {
            switch self {
            case .loadFailed: "Couldn’t Load Macs"
            case .persistenceFailed: "Changes Not Saved"
            }
        }

        var message: LocalizedStringResource {
            switch self {
            case .loadFailed: "OnlySwitch couldn’t load saved Macs. Your current screen was kept."
            case .persistenceFailed: "OnlySwitch couldn’t save the selected Mac and setup state."
            }
        }
    }

    enum Action: Equatable {
        case task
        case launchResponse(UInt64, LaunchResult)
        case persistenceResponse(RemoteAppPersistenceIntent, PersistenceResult)
        case retryTapped
        case settingsButtonTapped
        case scenePhaseChanged(Bool)
        case lifecycleResponse(UInt64)
        case requiredSettings(SettingsFeature.Action)
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
                    do {
                        let pairedMacs = try await persistence.loadPairedMacs()
                        let selectedMacID = try await persistence.loadSelectedMacID()
                        await send(.launchResponse(generation, .success(.init(
                            pairedMacs: pairedMacs,
                            selectedMacID: selectedMacID
                        ))))
                    } catch {
                        await send(.launchResponse(generation, .failure))
                    }
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .launchResponse(generation, .failure):
                guard generation == state.loadGeneration else { return .none }
                state.isLoading = false
                state.rootIssue = .loadFailed
                return .none

            case let .launchResponse(generation, .success(response)):
                guard generation == state.loadGeneration else { return .none }
                state.isLoading = false
                if state.rootIssue == .loadFailed { state.rootIssue = nil }
                let hadCompletedInitialSetup = state.hasCompletedInitialSetup
                state.pairedMacs = IdentifiedArray(uniqueElements: response.pairedMacs)
                guard let selected = selectedMac(
                    from: response.pairedMacs,
                    persistedID: response.selectedMacID
                ) else {
                    state.selectedMacID = nil
                    state.path.removeAll()
                    state.requiredSettings = .init(isSetupRequired: true)
                    state.hasCompletedInitialSetup = false
                    var effects: [Effect<Action>] = [
                        .run { [connection] _ in await connection.select(nil) }
                    ]
                    if hadCompletedInitialSetup || response.selectedMacID != nil {
                        effects.append(beginPersistence(
                            selectedMacID: nil,
                            hasCompletedInitialSetup: false,
                            state: &state
                        ))
                    }
                    return .merge(effects)
                }
                state.selectedMacID = selected.id
                state.requiredSettings = nil
                state.hasCompletedInitialSetup = true
                var effects: [Effect<Action>] = [
                    .run { [connection] _ in await connection.select(selected) }
                ]
                if hadCompletedInitialSetup == false || response.selectedMacID != selected.id {
                    effects.append(beginPersistence(
                        selectedMacID: selected.id,
                        hasCompletedInitialSetup: true,
                        state: &state
                    ))
                }
                return .merge(effects)

            case let .persistenceResponse(intent, .success):
                guard state.pendingPersistenceIntent == intent else { return .none }
                state.pendingPersistenceIntent = nil
                state.isPersisting = false
                if state.rootIssue == .persistenceFailed { state.rootIssue = nil }
                return .none

            case let .persistenceResponse(intent, .failure):
                guard state.pendingPersistenceIntent == intent else { return .none }
                state.isPersisting = false
                state.rootIssue = .persistenceFailed
                return .none

            case .retryTapped:
                if let intent = state.pendingPersistenceIntent, state.isPersisting == false {
                    state.isPersisting = true
                    return persist(intent)
                }
                if state.rootIssue == .loadFailed {
                    return .send(.task)
                }
                return .none

            case .settingsButtonTapped:
                guard state.requiredSettings == nil else { return .none }
                state.path.append(.settings(.init(
                    isSetupRequired: false,
                    pairedMacs: state.pairedMacs,
                    selectedMacID: state.selectedMacID
                )))
                return .none

            case let .scenePhaseChanged(foregrounded):
                state.isForegrounded = foregrounded
                state.lifecycleGeneration &+= 1
                let generation = state.lifecycleGeneration
                var effects: [Effect<Action>] = state.path.ids.compactMap { id in
                    guard case .settings = state.path[id: id] else { return nil }
                    return .send(.path(.element(id: id, action: .settings(.foregroundChanged(foregrounded)))))
                }
                if state.requiredSettings != nil {
                    effects.append(.send(.requiredSettings(.foregroundChanged(foregrounded))))
                }
                effects.append(
                    .run { [connection] send in
                        await connection.setForegrounded(foregrounded)
                        await send(.lifecycleResponse(generation))
                    }
                    .cancellable(id: CancelID.lifecycle, cancelInFlight: true)
                )
                return .merge(effects)

            case let .lifecycleResponse(generation):
                guard generation == state.lifecycleGeneration else { return .none }
                return .none

            case let .requiredSettings(.delegate(.paired(mac))):
                state.requiredSettings = nil
                state.hasCompletedInitialSetup = true
                return paired(mac, state: &state)

            case .requiredSettings(.delegate(.allMacsRemoved)):
                state.pairedMacs.removeAll()
                state.selectedMacID = nil
                state.requiredSettings = .init(isSetupRequired: true)
                state.hasCompletedInitialSetup = false
                return clearedSelection(state: &state)

            case let .path(.element(_, action: .settings(.delegate(.paired(mac))))):
                state.hasCompletedInitialSetup = true
                return paired(mac, state: &state)

            case .path(.element(_, action: .settings(.delegate(.allMacsRemoved)))):
                state.pairedMacs.removeAll()
                state.selectedMacID = nil
                state.path.removeAll()
                state.requiredSettings = .init(isSetupRequired: true)
                state.hasCompletedInitialSetup = false
                return clearedSelection(state: &state)

            case .requiredSettings, .path:
                return .none
            }
        }
        .ifLet(\.requiredSettings, action: \.requiredSettings) { SettingsFeature() }
        .forEach(\.path, action: \.path)
    }

    private func paired(_ mac: PairedMac, state: inout State) -> Effect<Action> {
        state.pairedMacs.updateOrAppend(mac)
        state.selectedMacID = mac.id
        state.rootIssue = nil
        return .merge(
            beginPersistence(
                selectedMacID: mac.id,
                hasCompletedInitialSetup: true,
                state: &state
            ),
            .run { [connection] _ in await connection.select(mac) }
        )
    }

    private func clearedSelection(state: inout State) -> Effect<Action> {
        state.rootIssue = nil
        return .merge(
            beginPersistence(
                selectedMacID: nil,
                hasCompletedInitialSetup: false,
                state: &state
            ),
            .run { [connection] _ in await connection.select(nil) }
        )
    }

    private func beginPersistence(
        selectedMacID: UUID?,
        hasCompletedInitialSetup: Bool,
        state: inout State
    ) -> Effect<Action> {
        state.nextPersistenceSequence += 1
        let intent = RemoteAppPersistenceIntent(
            writerID: state.persistenceWriterID,
            sequence: state.nextPersistenceSequence,
            selectedMacID: selectedMacID,
            hasCompletedInitialSetup: hasCompletedInitialSetup
        )
        state.pendingPersistenceIntent = intent
        state.isPersisting = true
        return persist(intent)
    }

    private func persist(_ intent: RemoteAppPersistenceIntent) -> Effect<Action> {
        .run { [persistence] send in
            do {
                try await persistence.saveAppState(intent)
                await send(.persistenceResponse(intent, .success))
            } catch {
                await send(.persistenceResponse(intent, .failure))
            }
        }
    }

    private func selectedMac(from macs: [PairedMac], persistedID: UUID?) -> PairedMac? {
        persistedID.flatMap { id in macs.first { $0.id == id } } ?? macs.first
    }
}

extension RemoteAppFeature.Path.State: Equatable {}
extension RemoteAppFeature.Path.Action: Equatable {}
