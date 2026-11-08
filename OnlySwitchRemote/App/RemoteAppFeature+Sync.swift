import ComposableArchitecture
import Foundation

extension RemoteAppFeature {
    func syncSettingsState(_ state: inout State) {
        let statuses = connectionStatuses(state)
        let pairedMacs = state.pairedMacs
        let selectedMacID = state.selectedMacID
        if var controlsConfiguration = state.controlsConfiguration {
            controlsConfiguration.pairedMacs = pairedMacs
            controlsConfiguration.selectedMacID = selectedMacID
            controlsConfiguration.connectionStatuses = statuses
            state.controlsConfiguration = controlsConfiguration
        }
        for id in state.path.ids {
            switch state.path[id: id] {
            case var .globalSettings(settings):
                settings.pairedMacs = state.pairedMacs
                settings.selectedMacID = state.selectedMacID
                settings.connectionStatuses = statuses
                state.path[id: id] = .globalSettings(settings)
            case var .controlsConfiguration(settings):
                settings.pairedMacs = state.pairedMacs
                settings.selectedMacID = state.selectedMacID
                settings.connectionStatuses = statuses
                state.path[id: id] = .controlsConfiguration(settings)
            case .monitorConfiguration, nil:
                continue
            }
        }
        syncSystemMonitorState(&state)
        syncSoundMixerState(&state)
        syncBrightnessState(&state)
        guard state.dashboard.isActive else { return }
        syncDashboardState(&state)
    }

    func syncDashboardState(_ state: inout State) {
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

    func forwardToDashboard(
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
        if state.soundMixer.isVisible {
            effects.append(.send(.soundMixer(.connectionEvent(event))))
        }
        if state.brightness.isVisible {
            effects.append(.send(.brightness(.connectionEvent(event))))
        }
        if state.screenshots.isVisible {
            effects.append(.send(.screenshots(.connectionEvent(event))))
        }
        return .merge(effects)
    }

    func soundMixerVisibility(state: State) -> Effect<Action> {
        let isVisible = state.isForegrounded && state.selectedPage == .soundMixer
        guard state.soundMixer.isVisible != isVisible else { return .none }
        return .send(.soundMixer(.visibilityChanged(isVisible)))
    }

    private func syncSoundMixerState(_ state: inout State) {
        let selectedID = state.selectedMacID
        if state.soundMixer.selectedMacID != selectedID {
            state.soundMixer.selectedMacID = selectedID
            state.soundMixer.snapshot = nil
            state.soundMixer.expandedAppIDs = []
            state.soundMixer.draftVolumes = [:]
            state.soundMixer.draftGains = [:]
            state.soundMixer.activeDrags = []
            state.soundMixer.availabilityMessage = nil
            state.soundMixer.commandError = nil
            state.soundMixer.isStreamRequested = false
            state.soundMixer.isStreaming = false
        }
        guard let selectedID else {
            state.soundMixer.connectionState = .idle
            return
        }
        if state.pairedMacs[id: selectedID]?.requiresPairing == true {
            state.soundMixer.connectionState = .revoked
        } else if state.connectedMacIDs.contains(selectedID) {
            state.soundMixer.connectionState = .authenticated
        } else if state.soundMixer.connectionState != .connecting {
            state.soundMixer.connectionState = .offline(nil)
        }
    }

    func brightnessVisibility(state: State) -> Effect<Action> {
        let isVisible = state.isForegrounded && state.selectedPage == .brightness
        guard state.brightness.isVisible != isVisible else { return .none }
        return .send(.brightness(.visibilityChanged(isVisible)))
    }

    private func syncBrightnessState(_ state: inout State) {
        let selectedID = state.selectedMacID
        if state.brightness.selectedMacID != selectedID {
            state.brightness.selectedMacID = selectedID
            state.brightness.snapshot = nil
            state.brightness.draftLevels = [:]
            state.brightness.activeDrags = []
            state.brightness.availabilityMessage = nil
            state.brightness.commandError = nil
            state.brightness.isStreamRequested = false
            state.brightness.isStreaming = false
        }
        guard let selectedID else {
            state.brightness.connectionState = .idle
            return
        }
        if state.pairedMacs[id: selectedID]?.requiresPairing == true {
            state.brightness.connectionState = .revoked
        } else if state.connectedMacIDs.contains(selectedID) {
            state.brightness.connectionState = .authenticated
        } else if state.brightness.connectionState != .connecting {
            state.brightness.connectionState = .offline(nil)
        }
    }

    func screenshotsVisibility(state: State) -> Effect<Action> {
        let isVisible = state.isForegrounded && state.selectedPage == .screenshots
        guard state.screenshots.isVisible != isVisible else { return .none }
        return .send(.screenshots(.visibilityChanged(isVisible)))
    }

    /// The root's view of the selected Mac, compared before and after each action.
    struct ScreenshotsContext: Equatable {
        let macID: UUID?
        let isConnected: Bool
        let requiresPairing: Bool

        init(_ state: State) {
            macID = state.selectedMacID
            isConnected = state.selectedMacID.map(state.connectedMacIDs.contains) ?? false
            requiresPairing = state.selectedMacID.flatMap { state.pairedMacs[id: $0]?.requiresPairing } ?? false
        }
    }

    /// Screenshots' counterpart of `syncBrightnessState`. It runs whenever an action changed the
    /// selected Mac or its connection/pairing state (where `syncSettingsState` re-syncs Brightness),
    /// and goes through `.contextChanged` instead of mutating child state, so the child cancels its
    /// own in-flight stream, thumbnail, image and delete work. Same state rules as Brightness.
    func syncScreenshotsContext(from before: ScreenshotsContext, after action: Action, state: State) -> Effect<Action> {
        let context = ScreenshotsContext(state)
        guard context != before else { return .none }
        let child = state.screenshots
        guard let macID = context.macID else {
            guard child.selectedMacID != nil || child.connectionState != .idle else { return .none }
            return .send(.screenshots(.contextChanged(macID: nil, connectionState: .idle)))
        }
        let connectionState: DashboardFeature.ConnectionState
        if context.requiresPairing {
            connectionState = .revoked
        } else if context.isConnected {
            connectionState = .authenticated
        } else {
            connectionState = .offline(nil)
        }
        if child.selectedMacID == macID {
            // A visible child received this Mac's event itself and keeps its own state.
            if case let .connectionEvent(event) = action, child.isVisible, event.connectionMacID == macID { return .none }
            switch (child.connectionState, connectionState) {
            case (.revoked, .revoked), (.authenticated, .authenticated), (.connecting, .offline), (.offline, .offline):
                return .none
            default:
                break
            }
        }
        return .send(.screenshots(.contextChanged(macID: macID, connectionState: connectionState)))
    }

    func loadSystemMonitorLayout(for macID: UUID, state: inout State) -> Effect<Action> {
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

    func selectedMac(from macs: [PairedMac], persistedID: UUID?) -> PairedMac? {
        persistedID.flatMap { id in macs.first { $0.id == id } } ?? macs.first
    }
}

private extension RemoteConnectionEvent {
    /// The Mac whose connection state this event reports, if any.
    var connectionMacID: UUID? {
        switch self {
        case let .connecting(id), let .sessionStarted(id, _), let .authenticated(id), let .offline(id, _), let .revoked(id):
            id
        case .persistenceRestored, .catalog, .catalogInvalidated, .statusSnapshot, .status, .action, .soundMixer,
             .systemMonitor, .brightness, .screenshots, .aphroditeLibraryChanged:
            nil
        }
    }
}
