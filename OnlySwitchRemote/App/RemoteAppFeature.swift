import ComposableArchitecture
import Foundation

enum RemoteAppPage: Hashable, Sendable {
    case controls
    case systemMonitor
}

@Reducer
struct RemoteAppFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()
        var requiredGlobalSettings: GlobalSettingsFeature.State?
        var pairedMacs: IdentifiedArrayOf<PairedMac> = []
        var selectedMacID: UUID?
        var dashboard = DashboardFeature.State()
        var selectedPage: RemoteAppPage = .controls
        var systemMonitor = RemoteSystemMonitorFeature.State()
        var systemMonitorLayoutGeneration: UInt64 = 0
        var connectedMacIDs: Set<UUID> = []
        var activeSessionID: UUID?
        var pairAdoptionGeneration: UInt64 = 0
        var connectionEventRevision: UInt64 = 0
        var metadataRefreshGeneration: UInt64 = 0
        var hasCompletedInitialSetup: Bool
        var isLoading = false
        var loadGeneration: UInt64 = 0
        var isForegrounded = true
        var isKeepingScreenAwake = RemoteIdleTimerClient.preferenceSeed()
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
                requiredGlobalSettings = .init(isSetupRequired: true)
            }
        }

        var requiresSetup: Bool { requiredGlobalSettings != nil }
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

    enum RemoteSystemMonitorLayoutLoadResult: Equatable, Sendable {
        case success(MacSystemMonitorLayout?)
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
        case systemMonitorLayoutLoaded(UInt64, UUID, RemoteSystemMonitorLayoutLoadResult)
        case retryTapped
        case globalSettingsButtonTapped
        case controlsConfigurationButtonTapped
        case macSelected(UUID)
        case scenePhaseChanged(Bool)
        case lifecycleResponse(UInt64)
        case pageSelected(RemoteAppPage)
        case dashboard(DashboardFeature.Action)
        case systemMonitor(RemoteSystemMonitorFeature.Action)
        case requiredGlobalSettings(GlobalSettingsFeature.Action)
        case path(StackActionOf<Path>)
    }
    @Reducer
    enum Path {
        case globalSettings(GlobalSettingsFeature)
        case controlsConfiguration(SettingsFeature)
        case monitorConfiguration(RemoteSystemMonitorConfigurationFeature)
    }

    @Dependency(\.remoteConnection) var connection
    @Dependency(\.remotePersistence) var persistence
    @Dependency(\.remoteIdleTimer) var idleTimer
    private enum CancelID { case load, lifecycle, connectionEvents, metadataRefresh }

    var body: some ReducerOf<Self> {
        Scope(state: \.dashboard, action: \.dashboard) { DashboardFeature() }
        Scope(state: \.systemMonitor, action: \.systemMonitor) { RemoteSystemMonitorFeature() }
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
                let keepScreenAwake = state.isForegrounded && state.isKeepingScreenAwake
                let idleTimerEffect = Effect<Action>.run { [idleTimer] _ in
                    await idleTimer.setIdleTimerDisabled(keepScreenAwake)
                }
                return .merge(load, events, idleTimerEffect)

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
                    state.requiredGlobalSettings = .init(isSetupRequired: true)
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
                state.requiredGlobalSettings = nil
                state.hasCompletedInitialSetup = true
                syncSettingsState(&state)
                var effects: [Effect<Action>] = [
                    .run { [connection] _ in await connection.select(selected) },
                    loadSystemMonitorLayout(for: selected.id, state: &state)
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
                case .persistenceRestored:
                    state.loadGeneration &+= 1
                    state.isLoading = true
                    let generation = state.loadGeneration
                    return .run { [persistence, connection] send in
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
                case .catalog, .catalogInvalidated, .statusSnapshot, .status, .action, .soundMixer, .systemMonitor:
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
                let previousSelectedMacID = state.selectedMacID
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
                guard previousSelectedMacID != state.selectedMacID,
                      let selectedMacID = state.selectedMacID else { return .none }
                return loadSystemMonitorLayout(for: selectedMacID, state: &state)

            case let .systemMonitorLayoutLoaded(generation, macID, result):
                guard generation == state.systemMonitorLayoutGeneration,
                      macID == state.selectedMacID else { return .none }
                switch result {
                case let .success(layout):
                    state.systemMonitor.layout = layout ?? .default(macID: macID)
                case .failure:
                    state.systemMonitor.layout = .default(macID: macID)
                }
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

            case .globalSettingsButtonTapped:
                guard state.requiredGlobalSettings == nil else { return .none }
                state.path.append(.globalSettings(.init(
                    isKeepingScreenAwake: state.isKeepingScreenAwake
                )))
                return .none

            case .controlsConfigurationButtonTapped:
                guard state.requiredGlobalSettings == nil,
                      state.selectedMacID != nil else { return .none }
                state.path.append(.controlsConfiguration(.init(
                    pairedMacs: state.pairedMacs,
                    selectedMacID: state.selectedMacID,
                    connectionStatuses: connectionStatuses(state)
                )))
                return .none

            case let .macSelected(id):
                guard let mac = state.pairedMacs[id: id] else { return .none }
                return select(mac, state: &state)

            case let .scenePhaseChanged(foregrounded):
                state.isForegrounded = foregrounded
                state.lifecycleGeneration &+= 1
                let generation = state.lifecycleGeneration
                let keepScreenAwake = foregrounded && state.isKeepingScreenAwake
                var effects: [Effect<Action>] = state.path.ids.compactMap { id in
                    switch state.path[id: id] {
                    case .globalSettings:
                        return .send(.path(.element(
                            id: id,
                            action: .globalSettings(.foregroundChanged(foregrounded))
                        )))
                    case .controlsConfiguration:
                        return .send(.path(.element(
                            id: id,
                            action: .controlsConfiguration(.foregroundChanged(foregrounded))
                        )))
                    case .monitorConfiguration, nil:
                        return nil
                    }
                }
                if state.requiredGlobalSettings != nil {
                    effects.append(.send(.requiredGlobalSettings(.foregroundChanged(foregrounded))))
                }
                if foregrounded == false, state.systemMonitor.isVisible {
                    effects.append(.send(.systemMonitor(.visibilityChanged(false))))
                } else if foregrounded, state.selectedPage == .systemMonitor {
                    effects.append(.send(.systemMonitor(.visibilityChanged(true))))
                }
                effects.append(
                    .run { [connection] send in
                        await connection.setForegrounded(foregrounded)
                        await send(.lifecycleResponse(generation))
                    }
                    .cancellable(id: CancelID.lifecycle, cancelInFlight: true)
                )
                effects.append(.run { [idleTimer] _ in
                    await idleTimer.setIdleTimerDisabled(keepScreenAwake)
                })
                return .merge(effects)

            case let .lifecycleResponse(generation):
                guard generation == state.lifecycleGeneration else { return .none }
                return .none

            case let .pageSelected(page):
                guard state.selectedPage != page else { return .none }
                state.selectedPage = page
                return .send(.systemMonitor(.visibilityChanged(page == .systemMonitor)))

            case .dashboard(.delegate(.openSettings)):
                return .send(.controlsConfigurationButtonTapped)

            case .systemMonitor(.delegate(.openConfiguration)):
                guard let selectedMacID = state.selectedMacID else { return .none }
                let layout = state.systemMonitor.layout ?? .default(macID: selectedMacID)
                state.path.append(.monitorConfiguration(.init(layout: layout)))
                return .none

            case let .dashboard(.delegate(.selectedMac(mac))):
                return select(mac, state: &state)

            case .dashboard(.task):
                let needsSynchronization = state.dashboard.pairedMacs != state.pairedMacs
                    || state.dashboard.selectedMacID != state.selectedMacID
                state.dashboard.isActive = true
                guard needsSynchronization else { return .none }
                syncDashboardState(&state)
                return .send(.dashboard(.task))

            case let .requiredGlobalSettings(.delegate(.paired(mac))):
                state.requiredGlobalSettings = nil
                state.hasCompletedInitialSetup = true
                return paired(mac, state: &state)

            case let .requiredGlobalSettings(.keepScreenAwakeToggled(isEnabled)):
                state.isKeepingScreenAwake = isEnabled
                let keepScreenAwake = state.isForegrounded && isEnabled
                return .run { [idleTimer] _ in
                    await idleTimer.setIdleTimerDisabled(keepScreenAwake)
                }

            case let .path(.element(_, action: .globalSettings(.delegate(.paired(mac))))):
                state.hasCompletedInitialSetup = true
                return paired(mac, state: &state)

            case let .path(.element(_, action: .globalSettings(.keepScreenAwakeToggled(isEnabled)))):
                state.isKeepingScreenAwake = isEnabled
                let keepScreenAwake = state.isForegrounded && isEnabled
                return .run { [idleTimer] _ in
                    await idleTimer.setIdleTimerDisabled(keepScreenAwake)
                }

            case let .path(.element(_, action: .controlsConfiguration(.delegate(.paired(mac))))):
                state.hasCompletedInitialSetup = true
                return paired(mac, state: &state)

            case let .path(.element(_, action: .controlsConfiguration(.delegate(.selectedMacChanged(mac))))):
                return select(mac, state: &state)

            case let .path(.element(_, action: .controlsConfiguration(.delegate(.layoutChanged(layout))))):
                guard state.dashboard.isActive else { return .none }
                return .send(.dashboard(.layoutChanged(layout)))

            case let .path(.element(_, action: .controlsConfiguration(.delegate(.macForgotten(id))))):
                state.pairedMacs.remove(id: id)
                state.connectedMacIDs.remove(id)
                invalidateMetadataRefresh(state: &state)
                syncSettingsState(&state)
                return .cancel(id: CancelID.metadataRefresh)

            case .path(.element(_, action: .controlsConfiguration(.delegate(.allMacsRemoved)))):
                state.pairedMacs.removeAll()
                state.connectedMacIDs.removeAll()
                state.selectedMacID = nil
                state.path.removeAll()
                state.requiredGlobalSettings = .init(isSetupRequired: true)
                state.hasCompletedInitialSetup = false
                invalidateMetadataRefresh(state: &state)
                return .merge(
                    .cancel(id: CancelID.metadataRefresh),
                    clearedSelection(state: &state)
                )

            case let .path(.element(_, action: .monitorConfiguration(.delegate(.layoutChanged(layout))))):
                guard state.selectedMacID == layout.macID else { return .none }
                state.systemMonitor.layout = layout
                return .none

            case .dashboard, .systemMonitor, .requiredGlobalSettings, .path:
                return .none
            }
        }
        .ifLet(\.requiredGlobalSettings, action: \.requiredGlobalSettings) { GlobalSettingsFeature() }
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
            .concatenate(persistenceEffect, adoptionEffect),
            loadSystemMonitorLayout(for: mac.id, state: &state)
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
            .run { [connection] _ in await connection.select(mac) },
            loadSystemMonitorLayout(for: mac.id, state: &state)
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
        state.systemMonitorLayoutGeneration &+= 1
        state.systemMonitor.layout = nil
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
        for pathID in state.path.ids {
            guard case var .controlsConfiguration(settings) = state.path[id: pathID] else { continue }
            settings.connectionStatuses[id] = status
            state.path[id: pathID] = .controlsConfiguration(settings)
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
        for id in state.path.ids {
            guard case var .controlsConfiguration(settings) = state.path[id: id] else { continue }
            settings.pairedMacs = state.pairedMacs
            settings.selectedMacID = state.selectedMacID
            settings.connectionStatuses = statuses
            state.path[id: id] = .controlsConfiguration(settings)
        }
        syncSystemMonitorState(&state)
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
            state.dashboard.actionFailures = [:]
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

    private func syncSystemMonitorState(_ state: inout State) {
        let selectedID = state.selectedMacID
        if state.systemMonitor.selectedMacID != selectedID {
            state.systemMonitor.selectedMacID = selectedID
            state.systemMonitor.snapshot = nil
            state.systemMonitor.history = .init()
            state.systemMonitor.expandedMetrics = []
            state.systemMonitor.availabilityMessage = nil
            state.systemMonitor.isStreaming = false
            state.systemMonitor.layout = selectedID.map { .default(macID: $0) }
        }
        guard let selectedID else {
            state.systemMonitor.connectionState = .idle
            return
        }
        if state.pairedMacs[id: selectedID]?.requiresPairing == true {
            state.systemMonitor.connectionState = .revoked
        } else if state.connectedMacIDs.contains(selectedID) {
            state.systemMonitor.connectionState = .authenticated
        } else if state.systemMonitor.connectionState != .connecting {
            state.systemMonitor.connectionState = .offline(nil)
        }
    }

    private func forwardToDashboard(
        _ event: RemoteConnectionEvent,
        alongside effect: Effect<Action> = .none,
        state: State
    ) -> Effect<Action> {
        var effects = [effect]
        if state.dashboard.isActive {
            effects.append(.send(.dashboard(.connectionEvent(event))))
        }
        if state.systemMonitor.isVisible {
            effects.append(.send(.systemMonitor(.connectionEvent(event))))
        }
        return .merge(effects)
    }

    private func loadSystemMonitorLayout(for macID: UUID, state: inout State) -> Effect<Action> {
        state.systemMonitorLayoutGeneration &+= 1
        let generation = state.systemMonitorLayoutGeneration
        state.systemMonitor.layout = .default(macID: macID)
        return .run { [persistence] send in
            do {
                let layout = try await persistence.loadSystemMonitorLayout(macID)
                await send(.systemMonitorLayoutLoaded(generation, macID, .success(layout)))
            } catch {
                await send(.systemMonitorLayoutLoaded(generation, macID, .failure))
            }
        }
    }

    private func selectedMac(from macs: [PairedMac], persistedID: UUID?) -> PairedMac? {
        persistedID.flatMap { id in macs.first { $0.id == id } } ?? macs.first
    }
}

extension RemoteAppFeature.Path.State: Equatable {}
extension RemoteAppFeature.Path.Action: Equatable {}
