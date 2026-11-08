import ComposableArchitecture
import Foundation

extension RemoteAppFeature {
    func reduceTask(_ state: inout State) -> Effect<Action> {
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
    }

    func reduceLaunchResponse(_ state: inout State, generation: UInt64, response: LaunchResponse) -> Effect<Action> {
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
            state.requiredGlobalSettings = .init(isSetupRequired: true, tabConfiguration: state.tabConfiguration)
            syncSettingsState(&state)
            state.hasCompletedInitialSetup = false
            var effects: [Effect<Action>] = [
                .run { [connection] _ in await connection.select(nil) },
                .send(.codexUsage(.contextChanged(macID: nil, sessionID: nil))), .send(.claudeUsage(.contextChanged(macID: nil, sessionID: nil))),
                .send(.aphrodite(.selectedMacChanged(nil)))
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
            loadSystemMonitorLayout(for: selected.id, state: &state),
            .send(.codexUsage(.contextChanged(macID: selected.id, sessionID: state.activeSessionID))), .send(.claudeUsage(.contextChanged(macID: selected.id, sessionID: state.activeSessionID))),
            .send(.aphrodite(.selectedMacChanged(selected.id)))
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
    }

    func reduceConnectionSnapshotLoaded(_ state: inout State, snapshot: RemoteConnectionSnapshot) -> Effect<Action> {
        state.connectedMacIDs = Set(snapshot.authenticatedMacID.map { [$0] } ?? [])
        state.activeSessionID = snapshot.authenticatedMacID == state.selectedMacID
            ? snapshot.authenticatedSessionID
            : nil
        syncSettingsState(&state)
        return .merge(.send(.codexUsage(.contextChanged(macID: state.selectedMacID, sessionID: state.activeSessionID))), .send(.claudeUsage(.contextChanged(macID: state.selectedMacID, sessionID: state.activeSessionID))))
    }

    func reduceConnectionEvent(_ state: inout State, event: RemoteConnectionEvent) -> Effect<Action> {
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
            guard id == state.selectedMacID else { return forwardToDashboard(event, state: state) }
            state.activeSessionID = nil
            if state.connectedMacIDs.contains(id) {
                state.connectedMacIDs.removeAll()
                syncSettingsState(&state)
            }
            updateConnectionStatus(.needsPairing, for: id, state: &state)
            return .merge(forwardToDashboard(event, alongside: refreshPairedMetadata(state: &state), state: state), .send(.codexUsage(.contextChanged(macID: state.selectedMacID, sessionID: nil))), .send(.claudeUsage(.contextChanged(macID: state.selectedMacID, sessionID: nil))))
        case let .offline(id, reason):
            guard id == state.selectedMacID else { return forwardToDashboard(event, state: state) }
            state.activeSessionID = nil
            if state.connectedMacIDs.contains(id) {
                state.connectedMacIDs.removeAll()
                syncSettingsState(&state)
            }
            updateConnectionStatus(.offline(reason), for: id, state: &state)
            return .merge(forwardToDashboard(event, state: state), .send(.codexUsage(.contextChanged(macID: state.selectedMacID, sessionID: nil))), .send(.claudeUsage(.contextChanged(macID: state.selectedMacID, sessionID: nil))))
        case let .connecting(id):
            guard id == state.selectedMacID else { return forwardToDashboard(event, state: state) }
            state.activeSessionID = nil
            state.connectedMacIDs.removeAll()
            syncSettingsState(&state)
            updateConnectionStatus(.connecting, for: id, state: &state)
            return .merge(forwardToDashboard(event, state: state), .send(.codexUsage(.contextChanged(macID: state.selectedMacID, sessionID: nil))), .send(.claudeUsage(.contextChanged(macID: state.selectedMacID, sessionID: nil))))
        case let .sessionStarted(macID, sessionID):
            guard macID == state.selectedMacID else { return forwardToDashboard(event, state: state) }
            state.activeSessionID = sessionID
            return .merge(forwardToDashboard(event, state: state), .send(.codexUsage(.contextChanged(macID: macID, sessionID: sessionID))), .send(.claudeUsage(.contextChanged(macID: macID, sessionID: sessionID))))
        case let .aphroditeLibraryChanged(macID, _):
            return .send(.aphrodite(.libraryChanged(macID)))
        case .catalog, .catalogInvalidated, .statusSnapshot, .status, .action, .soundMixer, .systemMonitor, .brightness, .screenshots:
            return forwardToDashboard(event, state: state)
        }
    }

    func reducePairAdoptionResponse(_ state: inout State, generation: UInt64, eventRevision: UInt64, id: UUID, result: RemotePairAdoptionResult) -> Effect<Action> {
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
    }

    func reducePairedMetadataRefreshed(_ state: inout State, generation: UInt64, macs: [PairedMac]) -> Effect<Action> {
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
            state.activeSessionID = nil
        }
        syncSettingsState(&state)
        guard previousSelectedMacID != state.selectedMacID else { return .none }
        guard let selectedMacID = state.selectedMacID else {
            return .merge(.send(.codexUsage(.contextChanged(macID: nil, sessionID: nil))), .send(.claudeUsage(.contextChanged(macID: nil, sessionID: nil))))
        }
        return .merge(
            loadSystemMonitorLayout(for: selectedMacID, state: &state),
            .send(.codexUsage(.contextChanged(macID: selectedMacID, sessionID: nil))), .send(.claudeUsage(.contextChanged(macID: selectedMacID, sessionID: nil)))
        )
    }

    func reduceSystemMonitorLayoutLoaded(_ state: inout State, generation: UInt64, macID: UUID, result: RemoteSystemMonitorLayoutLoadResult) -> Effect<Action> {
        guard generation == state.systemMonitorLayoutGeneration,
              macID == state.selectedMacID else { return .none }
        switch result {
        case let .success(layout):
            state.systemMonitor.layout = layout ?? .default(macID: macID)
        case .failure:
            state.systemMonitor.layout = .default(macID: macID)
        }
        return .none
    }
}
