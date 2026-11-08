import ComposableArchitecture
import Foundation

extension RemoteAppFeature {
    func paired(_ mac: PairedMac, state: inout State) -> Effect<Action> {
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
            loadSystemMonitorLayout(for: mac.id, state: &state),
            .send(.codexUsage(.contextChanged(macID: mac.id, sessionID: nil))), .send(.claudeUsage(.contextChanged(macID: mac.id, sessionID: nil))),
            .send(.aphrodite(.selectedMacChanged(mac.id)))
        ]
        if state.dashboard.isActive { effects.append(.send(.dashboard(.task))) }
        return .merge(effects)
    }

    func select(_ mac: PairedMac, state: inout State) -> Effect<Action> {
        guard state.pairedMacs[id: mac.id] != nil else { return .none }
        let activeActionIDs = state.dashboard.requestsInFlight
        state.selectedMacID = mac.id
        state.connectedMacIDs.removeAll()
        state.activeSessionID = nil
        if state.dashboard.isActive { state.dashboard.connectionState = .connecting }
        syncSettingsState(&state)
        state.rootIssue = nil
        var effects: [Effect<Action>] = [
            .send(.codexUsage(.contextChanged(macID: mac.id, sessionID: nil))), .send(.claudeUsage(.contextChanged(macID: mac.id, sessionID: nil))),
            .send(.aphrodite(.selectedMacChanged(mac.id))),
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

    func clearedSelection(state: inout State) -> Effect<Action> {
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
            .send(.codexUsage(.contextChanged(macID: nil, sessionID: nil))), .send(.claudeUsage(.contextChanged(macID: nil, sessionID: nil))),
            .send(.aphrodite(.selectedMacChanged(nil))),
            .merge(activeActionIDs.map {
                .cancel(id: DashboardFeature.CancelID.action($0))
            })
        )
    }

    func beginPersistence(
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

    func persist(_ intent: RemoteAppPersistenceIntent) -> Effect<Action> {
        .run { [persistence] send in
            do {
                try await persistence.saveAppState(intent)
                await send(.persistenceResponse(intent, .success))
            } catch {
                await send(.persistenceResponse(intent, .failure))
            }
        }
    }

    func refreshPairedMetadata(state: inout State) -> Effect<Action> {
        state.metadataRefreshGeneration &+= 1
        let generation = state.metadataRefreshGeneration
        return .run { [persistence] send in
            guard let macs = try? await persistence.loadPairedMacs() else { return }
            await send(.pairedMetadataRefreshed(generation, macs))
        }
        .cancellable(id: CancelID.metadataRefresh, cancelInFlight: true)
    }

    func invalidateMetadataRefresh(state: inout State) {
        state.metadataRefreshGeneration &+= 1
    }

    func updateConnectionStatus(
        _ status: MacConnectionStatus,
        for id: UUID,
        state: inout State
    ) {
        if state.controlsConfiguration != nil {
            state.controlsConfiguration?.connectionStatuses[id] = status
        }
        for pathID in state.path.ids {
            switch state.path[id: pathID] {
            case var .globalSettings(settings):
                settings.connectionStatuses[id] = status
                state.path[id: pathID] = .globalSettings(settings)
            case var .controlsConfiguration(settings):
                settings.connectionStatuses[id] = status
                state.path[id: pathID] = .controlsConfiguration(settings)
            case .monitorConfiguration, nil:
                continue
            }
        }
    }

    func connectionStatuses(_ state: State) -> [UUID: MacConnectionStatus] {
        Dictionary(uniqueKeysWithValues: state.pairedMacs.compactMap { mac in
            if mac.requiresPairing {
                return (mac.id, .needsPairing)
            } else if state.connectedMacIDs.contains(mac.id) {
                return (mac.id, .connected)
            }
            return nil
        })
    }
}
