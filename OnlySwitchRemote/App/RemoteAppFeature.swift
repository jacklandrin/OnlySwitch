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
        var dashboard = DashboardFeature.State()
        var connectedMacIDs: Set<UUID> = []
        var activeSessionID: UUID?
        var pairAdoptionGeneration: UInt64 = 0
        var connectionEventRevision: UInt64 = 0
        var metadataRefreshGeneration: UInt64 = 0
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
        let connectionSnapshot: RemoteConnectionSnapshot

        init(
            pairedMacs: [PairedMac],
            selectedMacID: UUID?,
            connectionSnapshot: RemoteConnectionSnapshot = .init()
        ) {
            self.pairedMacs = pairedMacs
            self.selectedMacID = selectedMacID
            self.connectionSnapshot = connectionSnapshot
        }
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
        case connectionSnapshotLoaded(RemoteConnectionSnapshot)
        case connectionEvent(RemoteConnectionEvent)
        case pairAdoptionResponse(UInt64, UInt64, UUID, RemotePairAdoptionResult)
        case pairedMetadataRefreshed(UInt64, [PairedMac])
        case persistenceResponse(RemoteAppPersistenceIntent, PersistenceResult)
        case retryTapped
        case settingsButtonTapped
        case scenePhaseChanged(Bool)
        case lifecycleResponse(UInt64)
        case dashboard(DashboardFeature.Action)
        case requiredSettings(SettingsFeature.Action)
        case path(StackActionOf<Path>)
    }
    @Reducer
    enum Path {
        case settings(SettingsFeature)
    }

    @Dependency(\.remoteConnection) var connection
    @Dependency(\.remotePersistence) var persistence
    private enum CancelID { case load, lifecycle, connectionEvents, metadataRefresh }

    var body: some ReducerOf<Self> {
        Scope(state: \.dashboard, action: \.dashboard) { DashboardFeature() }
        Reduce { state, action in
            switch action {
            case .task:
                state.loadGeneration &+= 1
                state.isLoading = true
                let generation = state.loadGeneration
                let load = Effect<Action>.run { [persistence, connection] send in
                    do {
                        async let pairedMacs = persistence.loadPairedMacs()
                        async let selectedMacID = persistence.loadSelectedMacID()
                        async let snapshot = connection.snapshot()
                        await send(.launchResponse(generation, .success(.init(
                            pairedMacs: try await pairedMacs,
                            selectedMacID: try await selectedMacID,
                            connectionSnapshot: await snapshot
                        ))))
                    } catch {
                        await send(.launchResponse(generation, .failure))
                    }
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)
                let events = Effect<Action>.run { [connection] send in
                    for await event in connection.events() {
                        try Task.checkCancellation()
                        await send(.connectionEvent(event))
                    }
                } catch: { _, _ in }
                    .cancellable(id: CancelID.connectionEvents, cancelInFlight: true)
                return .merge(load, events)

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
                state.connectedMacIDs = Set(response.connectionSnapshot.authenticatedMacID.map { [$0] } ?? [])
                state.activeSessionID = response.connectionSnapshot.authenticatedSessionID
                state.connectedMacIDs.formIntersection(response.pairedMacs.map(\.id))
                guard let selected = selectedMac(
                    from: response.pairedMacs,
                    persistedID: response.selectedMacID
                ) else {
                    state.selectedMacID = nil
                    state.path.removeAll()
                    state.requiredSettings = .init(isSetupRequired: true)
                    syncSettingsState(&state)
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
                state.connectedMacIDs.formIntersection([selected.id])
                if response.connectionSnapshot.authenticatedMacID != selected.id {
                    state.activeSessionID = nil
                }
                state.requiredSettings = nil
                state.hasCompletedInitialSetup = true
                syncSettingsState(&state)
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
                if state.dashboard.isActive { effects.append(.send(.dashboard(.task))) }
                return .merge(effects)

            case let .connectionSnapshotLoaded(snapshot):
                state.connectedMacIDs = Set(snapshot.authenticatedMacID.map { [$0] } ?? [])
                state.activeSessionID = snapshot.authenticatedMacID == state.selectedMacID
                    ? snapshot.authenticatedSessionID
                    : nil
                syncSettingsState(&state)
                return .none

            case let .connectionEvent(event):
                state.connectionEventRevision &+= 1
                switch event {
                case let .authenticated(id):
                    state.connectedMacIDs = [id]
                    syncSettingsState(&state)
                    return forwardToDashboard(event, alongside: refreshPairedMetadata(state: &state), state: state)
                case let .revoked(id):
                    state.activeSessionID = nil
                    if state.connectedMacIDs.contains(id) {
                        state.connectedMacIDs.removeAll()
                        syncSettingsState(&state)
                    }
                    updateConnectionStatus(.needsPairing, for: id, state: &state)
                    return forwardToDashboard(event, alongside: refreshPairedMetadata(state: &state), state: state)
                case let .offline(id, reason):
                    state.activeSessionID = nil
                    if state.connectedMacIDs.contains(id) {
                        state.connectedMacIDs.removeAll()
                        syncSettingsState(&state)
                    }
                    updateConnectionStatus(.offline(reason), for: id, state: &state)
                    return forwardToDashboard(event, state: state)
                case let .connecting(id):
                    state.activeSessionID = nil
                    state.connectedMacIDs.removeAll()
                    syncSettingsState(&state)
                    updateConnectionStatus(.connecting, for: id, state: &state)
                    return forwardToDashboard(event, state: state)
                case let .sessionStarted(_, sessionID):
                    state.activeSessionID = sessionID
                    return forwardToDashboard(event, state: state)
                case .catalog, .catalogInvalidated, .statusSnapshot, .status, .action:
                    return forwardToDashboard(event, state: state)
                }

            case let .pairAdoptionResponse(generation, eventRevision, id, result):
                guard generation == state.pairAdoptionGeneration,
                      eventRevision == state.connectionEventRevision,
                      state.selectedMacID == id else { return .none }
                switch result {
                case .authenticated:
                    state.connectedMacIDs = [id]
                case .connecting, .offline:
                    state.connectedMacIDs.removeAll()
                }
                syncSettingsState(&state)
                return .none

            case let .pairedMetadataRefreshed(generation, macs):
                guard generation == state.metadataRefreshGeneration else { return .none }
                let previousIDs = Set(state.pairedMacs.ids)
                state.pairedMacs = IdentifiedArray(uniqueElements: macs)
                if Set(state.pairedMacs.ids) != previousIDs {
                    invalidateMetadataRefresh(state: &state)
                }
                state.connectedMacIDs.formIntersection(macs.map(\.id))
                if let selectedMacID = state.selectedMacID,
                   state.pairedMacs[id: selectedMacID] == nil {
                    state.selectedMacID = state.pairedMacs.first?.id
                    state.connectedMacIDs.removeAll()
                }
                syncSettingsState(&state)
                return .none

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
                    selectedMacID: state.selectedMacID,
                    connectionStatuses: connectionStatuses(state)
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

            case .dashboard(.delegate(.openSettings)):
                return .send(.settingsButtonTapped)

            case let .dashboard(.delegate(.selectedMac(mac))):
                return select(mac, state: &state)

            case .dashboard(.task):
                let needsSynchronization = state.dashboard.pairedMacs != state.pairedMacs
                    || state.dashboard.selectedMacID != state.selectedMacID
                state.dashboard.isActive = true
                guard needsSynchronization else { return .none }
                syncDashboardState(&state)
                return .send(.dashboard(.task))

            case let .requiredSettings(.delegate(.paired(mac))):
                state.requiredSettings = nil
                state.hasCompletedInitialSetup = true
                return paired(mac, state: &state)

            case let .requiredSettings(.delegate(.selectedMacChanged(mac))):
                return select(mac, state: &state)

            case let .requiredSettings(.delegate(.layoutChanged(layout))):
                guard state.dashboard.isActive else { return .none }
                return .send(.dashboard(.layoutChanged(layout)))

            case let .requiredSettings(.delegate(.macForgotten(id))):
                state.pairedMacs.remove(id: id)
                state.connectedMacIDs.remove(id)
                invalidateMetadataRefresh(state: &state)
                syncSettingsState(&state)
                return .cancel(id: CancelID.metadataRefresh)

            case .requiredSettings(.delegate(.allMacsRemoved)):
                state.pairedMacs.removeAll()
                state.connectedMacIDs.removeAll()
                state.selectedMacID = nil
                state.requiredSettings = .init(isSetupRequired: true)
                state.hasCompletedInitialSetup = false
                invalidateMetadataRefresh(state: &state)
                return .merge(
                    .cancel(id: CancelID.metadataRefresh),
                    clearedSelection(state: &state)
                )

            case let .path(.element(_, action: .settings(.delegate(.paired(mac))))):
                state.hasCompletedInitialSetup = true
                return paired(mac, state: &state)

            case let .path(.element(_, action: .settings(.delegate(.selectedMacChanged(mac))))):
                return select(mac, state: &state)

            case let .path(.element(_, action: .settings(.delegate(.layoutChanged(layout))))):
                guard state.dashboard.isActive else { return .none }
                return .send(.dashboard(.layoutChanged(layout)))

            case let .path(.element(_, action: .settings(.delegate(.macForgotten(id))))):
                state.pairedMacs.remove(id: id)
                state.connectedMacIDs.remove(id)
                invalidateMetadataRefresh(state: &state)
                syncSettingsState(&state)
                return .cancel(id: CancelID.metadataRefresh)

            case .path(.element(_, action: .settings(.delegate(.allMacsRemoved)))):
                state.pairedMacs.removeAll()
                state.connectedMacIDs.removeAll()
                state.selectedMacID = nil
                state.path.removeAll()
                state.requiredSettings = .init(isSetupRequired: true)
                state.hasCompletedInitialSetup = false
                invalidateMetadataRefresh(state: &state)
                return .merge(
                    .cancel(id: CancelID.metadataRefresh),
                    clearedSelection(state: &state)
                )

            case .dashboard, .requiredSettings, .path:
                return .none
            }
        }
        .ifLet(\.requiredSettings, action: \.requiredSettings) { SettingsFeature() }
        .forEach(\.path, action: \.path)
    }

    private func paired(_ mac: PairedMac, state: inout State) -> Effect<Action> {
        state.pairedMacs.updateOrAppend(mac)
        state.selectedMacID = mac.id
        state.connectedMacIDs.formIntersection([mac.id])
        state.pairAdoptionGeneration &+= 1
        let adoptionGeneration = state.pairAdoptionGeneration
        let eventRevision = state.connectionEventRevision
        invalidateMetadataRefresh(state: &state)
        syncSettingsState(&state)
        state.rootIssue = nil
        let persistenceEffect = beginPersistence(
            selectedMacID: mac.id,
            hasCompletedInitialSetup: true,
            state: &state
        )
        let adoptionEffect = Effect<Action>.run { [connection] send in
            let result = await connection.adoptPairedMac(mac)
            await send(.pairAdoptionResponse(adoptionGeneration, eventRevision, mac.id, result))
        }
        var effects: [Effect<Action>] = [
            .cancel(id: CancelID.metadataRefresh),
            .concatenate(persistenceEffect, adoptionEffect)
        ]
        if state.dashboard.isActive { effects.append(.send(.dashboard(.task))) }
        return .merge(effects)
    }

    private func select(_ mac: PairedMac, state: inout State) -> Effect<Action> {
        guard state.pairedMacs[id: mac.id] != nil else { return .none }
        let activeActionIDs = state.dashboard.requestsInFlight
        state.selectedMacID = mac.id
        state.connectedMacIDs.removeAll()
        state.activeSessionID = nil
        if state.dashboard.isActive { state.dashboard.connectionState = .connecting }
        syncSettingsState(&state)
        state.rootIssue = nil
        var effects: [Effect<Action>] = [
            beginPersistence(
                selectedMacID: mac.id,
                hasCompletedInitialSetup: true,
                state: &state
            ),
            .run { [connection] _ in await connection.select(mac) }
        ]
        if state.dashboard.isActive { effects.append(.send(.dashboard(.task))) }
        effects.append(contentsOf: activeActionIDs.map {
            .cancel(id: DashboardFeature.CancelID.action($0))
        })
        return .merge(effects)
    }

    private func clearedSelection(state: inout State) -> Effect<Action> {
        let activeActionIDs = state.dashboard.requestsInFlight
        state.rootIssue = nil
        state.activeSessionID = nil
        syncDashboardState(&state)
        return .merge(
            beginPersistence(
                selectedMacID: nil,
                hasCompletedInitialSetup: false,
                state: &state
            ),
            .run { [connection] _ in await connection.select(nil) },
            .merge(activeActionIDs.map {
                .cancel(id: DashboardFeature.CancelID.action($0))
            })
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

    private func refreshPairedMetadata(state: inout State) -> Effect<Action> {
        state.metadataRefreshGeneration &+= 1
        let generation = state.metadataRefreshGeneration
        return .run { [persistence] send in
            guard let macs = try? await persistence.loadPairedMacs() else { return }
            await send(.pairedMetadataRefreshed(generation, macs))
        }
        .cancellable(id: CancelID.metadataRefresh, cancelInFlight: true)
    }

    private func invalidateMetadataRefresh(state: inout State) {
        state.metadataRefreshGeneration &+= 1
    }

    private func updateConnectionStatus(
        _ status: MacConnectionStatus,
        for id: UUID,
        state: inout State
    ) {
        if var settings = state.requiredSettings {
            settings.connectionStatuses[id] = status
            state.requiredSettings = settings
        }
        for pathID in state.path.ids {
            guard case var .settings(settings) = state.path[id: pathID] else { continue }
            settings.connectionStatuses[id] = status
            state.path[id: pathID] = .settings(settings)
        }
    }

    private func connectionStatuses(_ state: State) -> [UUID: MacConnectionStatus] {
        Dictionary(uniqueKeysWithValues: state.pairedMacs.compactMap { mac in
            if mac.requiresPairing {
                return (mac.id, .needsPairing)
            } else if state.connectedMacIDs.contains(mac.id) {
                return (mac.id, .connected)
            }
            return nil
        })
    }

    private func syncSettingsState(_ state: inout State) {
        let statuses = connectionStatuses(state)
        if var settings = state.requiredSettings {
            settings.pairedMacs = state.pairedMacs
            settings.selectedMacID = state.selectedMacID
            settings.connectionStatuses = statuses
            state.requiredSettings = settings
        }
        for id in state.path.ids {
            guard case var .settings(settings) = state.path[id: id] else { continue }
            settings.pairedMacs = state.pairedMacs
            settings.selectedMacID = state.selectedMacID
            settings.connectionStatuses = statuses
            state.path[id: id] = .settings(settings)
        }
        guard state.dashboard.isActive else { return }
        syncDashboardState(&state)
    }

    private func syncDashboardState(_ state: inout State) {
        let selectedID = state.selectedMacID
        let changedSelection = state.dashboard.selectedMacID != selectedID
        state.dashboard.pairedMacs = state.pairedMacs
        state.dashboard.selectedMacID = selectedID
        if changedSelection {
            state.dashboard.selectionGeneration &+= 1
            state.dashboard.descriptors = []
            state.dashboard.catalogRevision = 0
            state.dashboard.statuses = [:]
            state.dashboard.orderedSelectedIDs = []
            state.dashboard.requestsInFlight = []
            state.dashboard.requestIDs = [:]
            state.dashboard.retryInvocations = [:]
            state.dashboard.activeSessionID = nil
            state.dashboard.awaitingInitialCatalog = false
            state.dashboard.pendingCatalogRevision = nil
            state.dashboard.hasAcceptedLiveCatalog = false
            state.dashboard.liveStatusControlIDs = []
            state.dashboard.alert = nil
        }
        if let id = selectedID {
            if state.pairedMacs[id: id]?.requiresPairing == true {
                state.dashboard.connectionState = .revoked
            } else if state.connectedMacIDs.contains(id) {
                state.dashboard.connectionState = .authenticated
                state.dashboard.activeSessionID = state.activeSessionID
            } else if state.dashboard.connectionState != .connecting {
                state.dashboard.connectionState = .offline(nil)
                state.dashboard.activeSessionID = nil
            }
        } else {
            state.dashboard.connectionState = .idle
            state.dashboard.activeSessionID = nil
        }
    }

    private func forwardToDashboard(
        _ event: RemoteConnectionEvent,
        alongside effect: Effect<Action> = .none,
        state: State
    ) -> Effect<Action> {
        guard state.dashboard.isActive else { return effect }
        return .merge(effect, .send(.dashboard(.connectionEvent(event))))
    }

    private func selectedMac(from macs: [PairedMac], persistedID: UUID?) -> PairedMac? {
        persistedID.flatMap { id in macs.first { $0.id == id } } ?? macs.first
    }
}

extension RemoteAppFeature.Path.State: Equatable {}
extension RemoteAppFeature.Path.Action: Equatable {}
