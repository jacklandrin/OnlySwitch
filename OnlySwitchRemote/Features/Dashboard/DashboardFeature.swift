import ComposableArchitecture
import Foundation
import RemoteCore

@Reducer
struct DashboardFeature {
    enum ConnectionState: Equatable, Sendable {
        case idle
        case connecting
        case authenticated
        case offline(String?)
        case revoked
    }

    struct TileStatus: Equatable, Sendable {
        var value: RemoteControlStatus
        var isStale: Bool
    }

    @ObservableState
    struct State: Equatable {
        var pairedMacs: IdentifiedArrayOf<PairedMac>
        var selectedMacID: UUID?
        var descriptors: IdentifiedArrayOf<RemoteControlDescriptor>
        var catalogRevision: UInt64
        var statuses: [RemoteControlID: TileStatus]
        var orderedSelectedIDs: [RemoteControlID]
        var requestsInFlight: Set<RemoteControlID>
        var requestIDs: [RemoteControlID: UUID]
        var actionFailures: [RemoteControlID: String] = [:]
        var retryInvocations: [RemoteControlID: RemoteActionInvocation] = [:]
        var connectionState: ConnectionState
        var isActive: Bool
        var selectionGeneration: UInt64 = 0
        var activeSessionID: UUID?
        var awaitingInitialCatalog = false
        var pendingCatalogRevision: UInt64?
        var hasAcceptedLiveCatalog = false
        var liveStatusControlIDs: Set<RemoteControlID> = []
        @Presents var alert: AlertState<Action.Alert>?

        init(
            pairedMacs: IdentifiedArrayOf<PairedMac> = [],
            selectedMacID: UUID? = nil,
            descriptors: IdentifiedArrayOf<RemoteControlDescriptor> = [],
            catalogRevision: UInt64 = 0,
            statuses: [RemoteControlID: TileStatus] = [:],
            orderedSelectedIDs: [RemoteControlID] = [],
            requestsInFlight: Set<RemoteControlID> = [],
            requestIDs: [RemoteControlID: UUID] = [:],
            connectionState: ConnectionState = .idle,
            isActive: Bool = false
        ) {
            self.pairedMacs = pairedMacs
            self.selectedMacID = selectedMacID
            self.descriptors = descriptors
            self.catalogRevision = catalogRevision
            self.statuses = statuses
            self.orderedSelectedIDs = orderedSelectedIDs
            self.requestsInFlight = requestsInFlight
            self.requestIDs = requestIDs
            self.connectionState = connectionState
            self.isActive = isActive
        }

        var selectedMac: PairedMac? { selectedMacID.flatMap { pairedMacs[id: $0] } }
        var canSendActions: Bool {
            connectionState == .authenticated
                && selectedMac != nil
                && activeSessionID != nil
                && awaitingInitialCatalog == false
                && pendingCatalogRevision == nil
        }

        var visibleDescriptors: [RemoteControlDescriptor] {
            orderedSelectedIDs.compactMap { descriptors[id: $0] }
        }

        var subscriptionControlIDs: Set<RemoteControlID> {
            Set(visibleDescriptors.map(\.id))
        }

        var actionableControlIDs: Set<RemoteControlID> {
            Set(visibleDescriptors.lazy.map(\.id).filter(canTrigger))
        }

        func canTrigger(_ id: RemoteControlID) -> Bool {
            guard canSendActions,
                  requestsInFlight.contains(id) == false,
                  let descriptor = descriptors[id: id],
                  descriptor.isAvailable
            else { return false }
            if let status = statuses[id] {
                return status.isStale == false
                    && status.value.isAvailable
                    && status.value.isProcessing == false
            }
            return descriptor.supportsStatus == false
        }
    }

    enum LoadResult: Equatable, Sendable {
        case success(MacDashboardLayout?, RemoteCatalogCache?, [RemoteControlStatus])
        case failure
    }

    enum Action: Equatable {
        case task
        case selectedDataLoaded(UInt64, UUID, LoadResult)
        case subscriptionStarted(Set<RemoteControlID>)
        case subscriptionFailed(String)
        case synchronize(IdentifiedArrayOf<PairedMac>, UUID?, ConnectionState)
        case layoutChanged(MacDashboardLayout)
        case macSelected(UUID)
        case connectionEvent(RemoteConnectionEvent)
        case tileTapped(RemoteControlID)
        case actionResponse(RemoteControlID, UUID, Result<RemoteActionResult, RemoteProtocolError>)
        case actionCompleted(RemoteControlID, RemoteActionInvocation, Result<RemoteActionResult, RemoteProtocolError>)
        case menuTapped
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)

        enum Alert: Equatable {
            case confirmDestructive(RemoteControlID)
            case retryTimedOut(RemoteControlID)
            case cancelTimedOut(RemoteControlID)
        }
    }

    enum Delegate: Equatable {
        case openSettings
        case selectedMac(PairedMac)
    }

    @Dependency(\.remoteConnection) var connection
    @Dependency(\.remotePersistence) var persistence
    @Dependency(\.uuid) var uuid

    enum CancelID: Hashable { case selectedData, subscription, action(RemoteControlID) }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isActive = true
                var effects = [subscribe(state)]
                if let id = state.selectedMacID {
                    state.selectionGeneration &+= 1
                    effects.append(loadSelectedMac(id: id, generation: state.selectionGeneration))
                }
                return .merge(effects)

            case let .selectedDataLoaded(generation, id, .success(layout, cache, cachedStatuses)):
                guard generation == state.selectionGeneration, id == state.selectedMacID else { return .none }
                if let cache,
                   state.hasAcceptedLiveCatalog == false,
                   cache.revision > state.catalogRevision {
                    state.descriptors = IdentifiedArray(uniqueElements: cache.controls)
                    state.catalogRevision = cache.revision
                }
                state.orderedSelectedIDs = orderedIDs(from: layout)
                state.statuses = authoritativeStatuses(
                    cachedStatuses.filter { state.liveStatusControlIDs.contains($0.id) == false },
                    existing: state.statuses,
                    stale: true
                )
                return subscribe(state)

            case let .selectedDataLoaded(generation, id, .failure):
                guard generation == state.selectionGeneration, id == state.selectedMacID else { return .none }
                return subscribe(state)

            case .subscriptionStarted:
                return .none

            case let .subscriptionFailed(message):
                guard state.connectionState == .authenticated else { return .none }
                state.alert = .actionFailed(message: message)
                return .none

            case let .synchronize(macs, selectedID, connectionState):
                let changedSelection = selectedID != state.selectedMacID
                let activeActionIDs = state.requestsInFlight
                state.pairedMacs = macs
                state.selectedMacID = selectedID
                state.connectionState = connectionState
                guard changedSelection else { return .none }
                resetSelectionState(&state)
                guard let selectedID else {
                    return .merge(subscribe([]), cancelActions(activeActionIDs))
                }
                state.selectionGeneration &+= 1
                return .merge(
                    loadSelectedMac(id: selectedID, generation: state.selectionGeneration),
                    subscribe([]),
                    cancelActions(activeActionIDs)
                )

            case let .layoutChanged(layout):
                guard layout.macID == state.selectedMacID else { return .none }
                state.orderedSelectedIDs = orderedIDs(from: layout)
                return subscribe(state)

            case let .macSelected(id):
                guard let mac = state.pairedMacs[id: id], id != state.selectedMacID else { return .none }
                return .send(.delegate(.selectedMac(mac)))

            case let .connectionEvent(event):
                return handleConnectionEvent(event, state: &state)

            case let .tileTapped(id):
                guard state.canTrigger(id), let descriptor = state.descriptors[id: id] else { return .none }
                if descriptor.isDestructive {
                    state.alert = .confirmDestructive(
                        controlID: id,
                        controlTitle: descriptor.localizedTitle,
                        macName: state.selectedMac?.displayName ?? String(localized: "Mac")
                    )
                    return .none
                }
                return startAction(id, descriptor: descriptor, state: &state)

            case let .alert(.presented(.confirmDestructive(id))):
                guard state.canTrigger(id), let descriptor = state.descriptors[id: id] else { return .none }
                return startAction(id, descriptor: descriptor, state: &state)

            case let .alert(.presented(.retryTimedOut(id))):
                guard let invocation = state.retryInvocations.removeValue(forKey: id),
                      state.selectedMacID == invocation.macID,
                      state.activeSessionID == invocation.sessionID,
                      state.canTrigger(id)
                else { return .none }
                return sendAction(id, invocation: invocation, state: &state)

            case let .alert(.presented(.cancelTimedOut(id))):
                state.retryInvocations[id] = nil
                return .none

            case .alert:
                return .none

            case let .actionResponse(id, requestID, result):
                return handleActionResponse(id: id, requestID: requestID, response: result, state: &state)

            case let .actionCompleted(id, invocation, result):
                guard state.requestIDs[id] == invocation.request.requestID else { return .none }
                if case let .failure(error) = result, error.code == .requestTimedOut {
                    state.requestsInFlight.remove(id)
                    state.requestIDs[id] = nil
                    state.retryInvocations[id] = invocation
                    state.alert = .actionTimedOut(
                        controlID: id,
                        destructive: state.descriptors[id: id]?.isDestructive == true
                    )
                    return .none
                }
                return handleActionResponse(
                    id: id,
                    requestID: invocation.request.requestID,
                    response: result,
                    state: &state
                )

            case .menuTapped:
                return .send(.delegate(.openSettings))

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    private func loadSelectedMac(id: UUID, generation: UInt64) -> Effect<Action> {
        .run { [persistence] send in
            do {
                async let layout = persistence.loadLayout(id)
                async let catalog = persistence.loadCatalog(id)
                async let statuses = persistence.loadStatuses(id)
                await send(.selectedDataLoaded(
                    generation,
                    id,
                    .success(try await layout, try await catalog, try await statuses ?? [])
                ))
            } catch {
                await send(.selectedDataLoaded(generation, id, .failure))
            }
        }
        .cancellable(id: CancelID.selectedData, cancelInFlight: true)
    }

    func subscribe(_ state: State) -> Effect<Action> {
        guard state.hasAcceptedLiveCatalog else { return .none }
        return subscribe(state.subscriptionControlIDs)
    }

    private func subscribe(_ selection: Set<RemoteControlID>) -> Effect<Action> {
        return .run { [connection] send in
            do {
                try await connection.subscribe(selection)
                await send(.subscriptionStarted(selection))
            } catch {
                await send(.subscriptionFailed(userSafeMessage(error)))
            }
        }
        .cancellable(id: CancelID.subscription, cancelInFlight: true)
    }

    func apply(_ status: RemoteControlStatus, to state: inout State) {
        guard status.revision > (state.statuses[status.id]?.value.revision ?? 0) else { return }
        state.actionFailures[status.id] = nil
        state.statuses[status.id] = .init(value: status, isStale: false)
    }

    private func resetSelectionState(_ state: inout State) {
        state.selectionGeneration &+= 1
        state.activeSessionID = nil
        state.awaitingInitialCatalog = false
        state.pendingCatalogRevision = nil
        state.hasAcceptedLiveCatalog = false
        state.liveStatusControlIDs.removeAll()
        state.descriptors = []
        state.catalogRevision = 0
        state.statuses = [:]
        state.orderedSelectedIDs = []
        state.actionFailures.removeAll()
        clearRequests(&state)
        state.retryInvocations.removeAll()
        state.alert = nil
    }

    private func clearRequests(_ state: inout State) {
        state.requestsInFlight.removeAll()
        state.requestIDs.removeAll()
    }

    func cancelActiveActions(_ state: inout State) -> Effect<Action> {
        let ids = state.requestsInFlight
        clearRequests(&state)
        state.retryInvocations.removeAll()
        return cancelActions(ids)
    }

    private func cancelActions(_ ids: Set<RemoteControlID>) -> Effect<Action> {
        .merge(ids.map { .cancel(id: CancelID.action($0)) })
    }

    func markStatusesStale(_ state: inout State) {
        for id in state.statuses.keys { state.statuses[id]?.isStale = true }
    }

    private func orderedIDs(from layout: MacDashboardLayout?) -> [RemoteControlID] {
        guard let layout else { return [] }
        return layout.order.filter(layout.selectedControlIDs.contains)
            + layout.selectedControlIDs.filter { layout.order.contains($0) == false }
    }

    private func authoritativeStatuses(
        _ incoming: [RemoteControlStatus],
        existing: [RemoteControlID: TileStatus],
        stale: Bool
    ) -> [RemoteControlID: TileStatus] {
        var result = existing
        for status in incoming where status.revision > (result[status.id]?.value.revision ?? 0) {
            result[status.id] = .init(value: status, isStale: stale)
        }
        return result
    }

    private func userSafeMessage(_ error: any Error) -> String {
        (error as? RemoteProtocolError)?.message ?? String(localized: "The Mac could not be reached.")
    }
}
