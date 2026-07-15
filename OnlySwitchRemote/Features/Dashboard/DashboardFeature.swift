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
        var connectionState: ConnectionState
        var isActive: Bool
        var selectionGeneration: UInt64 = 0
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
        var canSendActions: Bool { connectionState == .authenticated && selectedMac != nil }

        var visibleDescriptors: [RemoteControlDescriptor] {
            orderedSelectedIDs.compactMap { descriptors[id: $0] }
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
                return status.isStale == false && status.value.isAvailable
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
        case menuTapped
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)

        enum Alert: Equatable {
            case confirmDestructive(RemoteControlID)
        }
    }

    enum Delegate: Equatable {
        case openSettings
        case selectedMac(PairedMac)
    }

    @Dependency(\.remoteConnection) var connection
    @Dependency(\.remotePersistence) var persistence
    @Dependency(\.uuid) var uuid

    private enum CancelID: Hashable { case selectedData, subscription, action(RemoteControlID) }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isActive = true
                var effects = [subscribe(state.orderedSelectedIDs)]
                if let id = state.selectedMacID {
                    state.selectionGeneration &+= 1
                    effects.append(loadSelectedMac(id: id, generation: state.selectionGeneration))
                }
                return .merge(effects)

            case let .selectedDataLoaded(generation, id, .success(layout, cache, cachedStatuses)):
                guard generation == state.selectionGeneration, id == state.selectedMacID else { return .none }
                if let cache, cache.revision > state.catalogRevision {
                    state.descriptors = IdentifiedArray(uniqueElements: cache.controls)
                    state.catalogRevision = cache.revision
                }
                state.orderedSelectedIDs = orderedIDs(from: layout)
                state.statuses = authoritativeStatuses(
                    cachedStatuses,
                    existing: state.statuses,
                    stale: state.connectionState != .authenticated
                )
                return subscribe(state.orderedSelectedIDs)

            case let .selectedDataLoaded(generation, id, .failure):
                guard generation == state.selectionGeneration, id == state.selectedMacID else { return .none }
                return subscribe(state.orderedSelectedIDs)

            case .subscriptionStarted:
                return .none

            case let .subscriptionFailed(message):
                guard state.connectionState == .authenticated else { return .none }
                state.alert = .actionFailed(message: message)
                return .none

            case let .synchronize(macs, selectedID, connectionState):
                let changedSelection = selectedID != state.selectedMacID
                state.pairedMacs = macs
                state.selectedMacID = selectedID
                state.connectionState = connectionState
                guard changedSelection else { return .none }
                resetSelectionState(&state)
                guard let selectedID else { return subscribe([]) }
                state.selectionGeneration &+= 1
                return .merge(
                    loadSelectedMac(id: selectedID, generation: state.selectionGeneration),
                    subscribe([])
                )

            case let .layoutChanged(layout):
                guard layout.macID == state.selectedMacID else { return .none }
                state.orderedSelectedIDs = orderedIDs(from: layout)
                return subscribe(state.orderedSelectedIDs)

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
                        controlTitle: descriptor.title,
                        macName: state.selectedMac?.displayName ?? String(localized: "Mac")
                    )
                    return .none
                }
                return startAction(id, descriptor: descriptor, state: &state)

            case let .alert(.presented(.confirmDestructive(id))):
                guard state.canTrigger(id), let descriptor = state.descriptors[id: id] else { return .none }
                return startAction(id, descriptor: descriptor, state: &state)

            case .alert:
                return .none

            case let .actionResponse(id, requestID, result):
                return handleActionResponse(id: id, requestID: requestID, response: result, state: &state)

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

    private func subscribe(_ ids: [RemoteControlID]) -> Effect<Action> {
        let selection = Set(ids)
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

    private func startAction(
        _ id: RemoteControlID,
        descriptor: RemoteControlDescriptor,
        state: inout State
    ) -> Effect<Action> {
        let action: RemoteControlAction
        switch descriptor.behavior {
        case .button:
            action = .trigger
        case .switch, .player:
            action = .setState(!(state.statuses[id]?.value.isOn ?? false))
        }
        let request = RemoteActionRequest(requestID: uuid(), controlID: id, action: action)
        state.requestsInFlight.insert(id)
        state.requestIDs[id] = request.requestID
        return .run { [connection] send in
            do {
                await send(.actionResponse(id, request.requestID, .success(try await connection.send(request))))
            } catch let error as RemoteProtocolError {
                await send(.actionResponse(id, request.requestID, .failure(error)))
            } catch {
                await send(.actionResponse(id, request.requestID, .failure(.init(
                    code: .executionFailed,
                    message: String(localized: "The Mac could not complete this action.")
                ))))
            }
        }
        .cancellable(id: CancelID.action(id), cancelInFlight: true)
    }

    private func handleActionResponse(
        id: RemoteControlID,
        requestID: UUID,
        response: Result<RemoteActionResult, RemoteProtocolError>,
        state: inout State
    ) -> Effect<Action> {
        guard state.requestIDs[id] == requestID else { return .none }
        switch response {
        case let .failure(error):
            state.requestsInFlight.remove(id)
            state.requestIDs[id] = nil
            state.alert = .actionFailed(message: error.message)
        case let .success(result):
            guard result.requestID == requestID else { return .none }
            state.requestsInFlight.remove(id)
            state.requestIDs[id] = nil
            switch result.result {
            case let .failure(error):
                state.alert = .actionFailed(message: error.message)
            case let .success(status):
                if let status { apply(status, to: &state) }
            }
        }
        return .none
    }

    private func handleConnectionEvent(
        _ event: RemoteConnectionEvent,
        state: inout State
    ) -> Effect<Action> {
        let macID: UUID
        switch event {
        case let .connecting(id), let .authenticated(id), let .offline(id, _), let .revoked(id),
             let .catalog(id, _, _), let .status(id, _), let .action(id, _):
            macID = id
        }
        guard macID == state.selectedMacID else { return .none }

        switch event {
        case .connecting:
            state.connectionState = .connecting
            markStatusesStale(&state)
        case .authenticated:
            state.connectionState = .authenticated
            return subscribe(state.orderedSelectedIDs)
        case let .offline(_, reason):
            state.connectionState = .offline(reason)
            markStatusesStale(&state)
            clearRequests(&state)
        case .revoked:
            state.connectionState = .revoked
            markStatusesStale(&state)
            clearRequests(&state)
        case let .catalog(_, revision, controls):
            guard revision > state.catalogRevision else { return .none }
            state.catalogRevision = revision
            state.descriptors = IdentifiedArray(uniqueElements: controls)
        case let .status(_, status):
            apply(status, to: &state)
        case let .action(_, result):
            guard let id = state.requestIDs.first(where: { $0.value == result.requestID })?.key else { return .none }
            return handleActionResponse(
                id: id,
                requestID: result.requestID,
                response: .success(result),
                state: &state
            )
        }
        return .none
    }

    private func apply(_ status: RemoteControlStatus, to state: inout State) {
        guard status.revision > (state.statuses[status.id]?.value.revision ?? 0) else { return }
        state.statuses[status.id] = .init(value: status, isStale: false)
    }

    private func resetSelectionState(_ state: inout State) {
        state.selectionGeneration &+= 1
        state.descriptors = []
        state.catalogRevision = 0
        state.statuses = [:]
        state.orderedSelectedIDs = []
        clearRequests(&state)
        state.alert = nil
    }

    private func clearRequests(_ state: inout State) {
        state.requestsInFlight.removeAll()
        state.requestIDs.removeAll()
    }

    private func markStatusesStale(_ state: inout State) {
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

extension AlertState where Action == DashboardFeature.Action.Alert {
    static func confirmDestructive(
        controlID: RemoteControlID,
        controlTitle: String,
        macName: String
    ) -> Self {
        AlertState {
            TextState(String(localized: "Run \(controlTitle)?"))
        } actions: {
            ButtonState(role: .destructive, action: .confirmDestructive(controlID)) {
                TextState("Run")
            }
            ButtonState(role: .cancel) { TextState("Cancel") }
        } message: {
            TextState(String(localized: "This will run \(controlTitle) on \(macName)."))
        }
    }

    static func actionFailed(message: String) -> Self {
        AlertState {
            TextState("Action Failed")
        } actions: {
            ButtonState(role: .cancel) { TextState("OK") }
        } message: {
            TextState(message)
        }
    }
}
