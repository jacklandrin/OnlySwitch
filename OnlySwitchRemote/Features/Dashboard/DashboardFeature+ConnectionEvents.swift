import ComposableArchitecture
import Foundation
import RemoteCore

extension DashboardFeature {
    func handleConnectionEvent(
        _ event: RemoteConnectionEvent,
        state: inout State
    ) -> Effect<Action> {
        if case .persistenceRestored = event { return .none }
        let macID: UUID
        switch event {
        case .persistenceRestored:
            return .none
        case let .connecting(id), let .authenticated(id), let .offline(id, _), let .revoked(id),
             let .sessionStarted(id, _), let .catalog(id, _, _), let .catalogInvalidated(id, _),
             let .statusSnapshot(id, _), let .status(id, _), let .action(id, _), let .soundMixer(id, _),
             let .systemMonitor(id, _), let .brightness(id, _), let .screenshots(id, _), let .aphroditeLibraryChanged(id, _):
            macID = id
        }
        guard macID == state.selectedMacID else { return .none }

        switch event {
        case .persistenceRestored:
            return .none
        case .connecting:
            state.connectionState = .connecting
            state.activeSessionID = nil
            markStatusesStale(&state)
            return cancelActiveActions(&state)
        case let .sessionStarted(_, sessionID):
            state.activeSessionID = sessionID
            state.awaitingInitialCatalog = true
            state.pendingCatalogRevision = nil
            state.hasAcceptedLiveCatalog = false
            state.liveStatusControlIDs.removeAll()
            markStatusesStale(&state)
            return cancelActiveActions(&state)
        case .authenticated:
            state.connectionState = .authenticated
            return subscribe(state)
        case let .offline(_, reason):
            state.connectionState = .offline(reason)
            state.activeSessionID = nil
            state.awaitingInitialCatalog = false
            state.pendingCatalogRevision = nil
            state.hasAcceptedLiveCatalog = false
            markStatusesStale(&state)
            return cancelActiveActions(&state)
        case .revoked:
            state.connectionState = .revoked
            state.activeSessionID = nil
            markStatusesStale(&state)
            return cancelActiveActions(&state)
        case let .catalog(_, revision, controls):
            guard state.awaitingInitialCatalog || revision > state.catalogRevision || revision == state.pendingCatalogRevision else { return .none }
            state.catalogRevision = revision
            state.descriptors = IdentifiedArray(uniqueElements: controls)
            state.awaitingInitialCatalog = false
            state.pendingCatalogRevision = nil
            state.hasAcceptedLiveCatalog = true
            guard state.connectionState == .authenticated else { return .none }
            return subscribe(state)
        case let .catalogInvalidated(_, revision):
            guard state.awaitingInitialCatalog || revision > state.catalogRevision else { return .none }
            state.pendingCatalogRevision = revision
        case let .statusSnapshot(_, statuses):
            for status in statuses {
                if state.liveStatusControlIDs.insert(status.id).inserted {
                    state.statuses[status.id] = .init(value: status, isStale: false)
                    state.actionFailures[status.id] = nil
                } else {
                    apply(status, to: &state)
                }
            }
        case let .status(_, status):
            if state.liveStatusControlIDs.insert(status.id).inserted {
                state.statuses[status.id] = .init(value: status, isStale: false)
                state.actionFailures[status.id] = nil
            } else {
                apply(status, to: &state)
            }
        case let .action(_, result):
            guard let id = state.requestIDs.first(where: { $0.value == result.requestID })?.key else { return .none }
            return handleActionResponse(
                id: id,
                requestID: result.requestID,
                response: .success(result),
                state: &state
            )
        case .soundMixer, .systemMonitor, .brightness, .screenshots, .aphroditeLibraryChanged:
            return .none
        }
        return .none
    }
}
