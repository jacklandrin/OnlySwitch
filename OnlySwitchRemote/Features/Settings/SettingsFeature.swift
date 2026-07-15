import ComposableArchitecture
import Foundation
import RemoteCore

@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        let isSetupRequired: Bool
        var pairedMacs: IdentifiedArrayOf<PairedMac>
        var selectedMacID: UUID?
        var catalog: IdentifiedArrayOf<RemoteControlDescriptor>
        var catalogRevision: UInt64
        var selectedControlIDs: Set<RemoteControlID>
        var order: [RemoteControlID]
        var connectionStatuses: [UUID: MacConnectionStatus] = [:]
        var selectionGeneration: UInt64 = 0
        var isObservingConnectionEvents = false
        var pendingLayoutSaves: [UUID: MacDashboardLayout] = [:]
        var layoutSaveGenerations: [UUID: UInt64] = [:]
        var layoutSaveInFlight: Set<UUID> = []
        var layoutSaveIssueMacIDs: Set<UUID> = []
        @Presents var pairing: PairingFeature.State?
        @Presents var management: MacManagementFeature.State?

        init(
            isSetupRequired: Bool,
            pairedMacs: IdentifiedArrayOf<PairedMac> = [],
            selectedMacID: UUID? = nil,
            catalog: IdentifiedArrayOf<RemoteControlDescriptor> = [],
            catalogRevision: UInt64 = 0,
            selectedControlIDs: Set<RemoteControlID> = [],
            order: [RemoteControlID] = []
        ) {
            self.isSetupRequired = isSetupRequired
            self.pairedMacs = pairedMacs
            self.selectedMacID = selectedMacID
            self.catalog = catalog
            self.catalogRevision = catalogRevision
            self.selectedControlIDs = selectedControlIDs
            self.order = order
        }

        var selectedMac: PairedMac? { selectedMacID.flatMap { pairedMacs[id: $0] } }

        func controls(kind: RemoteControlID.Kind) -> [RemoteControlDescriptor] {
            catalog.filter { $0.id.kind == kind }
        }

        var orderedVisibleSelectedControlIDs: [RemoteControlID] {
            let descriptors = Set(catalog.ids)
            return order.filter { selectedControlIDs.contains($0) && descriptors.contains($0) }
        }
    }

    enum OperationResult: Equatable, Sendable { case success, failure }

    enum Action: Equatable {
        case task
        case selectedMacChanged(UUID)
        case selectedMacDataLoaded(UInt64, UUID, MacDashboardLayout?, RemoteCatalogCache?)
        case connectionEvent(RemoteConnectionEvent)
        case connectionEventsFinished
        case catalogCacheSaveResponse(UUID, UInt64, OperationResult)
        case toggleControl(RemoteControlID, Bool)
        case move(IndexSet, Int)
        case layoutSaveResponse(UUID, UInt64, MacDashboardLayout, OperationResult)
        case retryLayoutSave(UUID)
        case pairAnotherTapped
        case manageMac(UUID)
        case pairing(PresentationAction<PairingFeature.Action>)
        case management(PresentationAction<MacManagementFeature.Action>)
        case foregroundChanged(Bool)
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case paired(PairedMac)
        case selectedMacChanged(PairedMac)
        case macForgotten(UUID)
        case allMacsRemoved
    }

    @Dependency(\.remoteConnection) var connection
    @Dependency(\.remotePersistence) var persistence

    private enum CancelID { case selectedMacLoad, connectionEvents }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.isObservingConnectionEvents = true
                var effects: [Effect<Action>] = [observeConnectionEvents()]
                if let id = state.selectedMacID {
                    state.selectionGeneration &+= 1
                    effects.append(loadSelectedMac(id: id, generation: state.selectionGeneration))
                }
                return .merge(effects)

            case let .selectedMacChanged(id):
                guard let mac = state.pairedMacs[id: id], id != state.selectedMacID else { return .none }
                state.selectedMacID = id
                state.selectionGeneration &+= 1
                state.catalog = []
                state.catalogRevision = 0
                state.selectedControlIDs = []
                state.order = []
                let generation = state.selectionGeneration
                return .concatenate(
                    .send(.delegate(.selectedMacChanged(mac))),
                    loadSelectedMac(id: id, generation: generation)
                )

            case let .selectedMacDataLoaded(generation, id, layout, cache):
                guard generation == state.selectionGeneration, id == state.selectedMacID else { return .none }
                state.catalog = IdentifiedArray(uniqueElements: cache?.controls ?? [])
                state.catalogRevision = cache?.revision ?? 0
                let effectiveLayout = state.pendingLayoutSaves[id] ?? layout
                state.selectedControlIDs = effectiveLayout?.selectedControlIDs ?? []
                state.order = effectiveLayout?.order ?? []
                return .none

            case let .connectionEvent(event):
                return handleConnectionEvent(event, state: &state)

            case .connectionEventsFinished:
                state.isObservingConnectionEvents = false
                return .none

            case .catalogCacheSaveResponse:
                return .none

            case let .toggleControl(id, isSelected):
                guard state.catalog[id: id] != nil, let macID = state.selectedMacID else { return .none }
                if isSelected {
                    state.selectedControlIDs.insert(id)
                    if state.order.contains(id) == false { state.order.append(id) }
                } else {
                    state.selectedControlIDs.remove(id)
                    state.order.removeAll { $0 == id }
                }
                return enqueueLayoutSave(macID: macID, state: &state)

            case let .move(source, destination):
                guard let macID = state.selectedMacID else { return .none }
                let visible = state.orderedVisibleSelectedControlIDs
                guard source.allSatisfy(visible.indices.contains), destination >= 0, destination <= visible.count else { return .none }
                let reordered = moving(visible, from: source, to: destination)
                let visibleSet = Set(visible)
                var iterator = reordered.makeIterator()
                state.order = state.order.map { visibleSet.contains($0) ? (iterator.next() ?? $0) : $0 }
                return enqueueLayoutSave(macID: macID, state: &state)

            case let .layoutSaveResponse(macID, generation, savedLayout, result):
                guard state.layoutSaveGenerations[macID] == generation else { return .none }
                state.layoutSaveInFlight.remove(macID)
                switch result {
                case .failure:
                    state.layoutSaveIssueMacIDs.insert(macID)
                    return .none
                case .success:
                    state.layoutSaveIssueMacIDs.remove(macID)
                    guard let pending = state.pendingLayoutSaves[macID] else { return .none }
                    if pending == savedLayout { state.pendingLayoutSaves[macID] = nil; return .none }
                    return startLayoutSave(pending, state: &state)
                }

            case let .retryLayoutSave(macID):
                guard state.layoutSaveInFlight.contains(macID) == false,
                      let pending = state.pendingLayoutSaves[macID]
                else { return .none }
                return startLayoutSave(pending, state: &state)

            case .pairAnotherTapped:
                state.pairing = PairingFeature.State()
                return .none

            case let .manageMac(id):
                guard let mac = state.pairedMacs[id: id] else { return .none }
                let status = mac.requiresPairing ? .needsPairing : (state.connectionStatuses[id] ?? .unknown)
                state.management = .init(mac: mac, connectionStatus: status)
                return .none

            case let .pairing(.presented(.delegate(.paired(mac)))):
                state.pairing = nil
                state.pairedMacs.updateOrAppend(mac)
                state.selectedMacID = mac.id
                state.selectionGeneration &+= 1
                state.catalog = []
                state.catalogRevision = 0
                state.selectedControlIDs = []
                state.order = []
                let generation = state.selectionGeneration
                return .concatenate(
                    .send(.delegate(.paired(mac))),
                    loadSelectedMac(id: mac.id, generation: generation)
                )

            case .pairing(.presented(.delegate(.cancelled))):
                state.pairing = nil
                return .none

            case .pairing(.dismiss):
                return .none

            case let .management(.presented(.delegate(.rePair(id)))):
                guard state.pairedMacs[id: id] != nil else { return .none }
                state.management = nil
                state.pairing = PairingFeature.State()
                return .none

            case let .management(.presented(.delegate(.forgotten(id)))):
                state.management = nil
                let wasSelected = state.selectedMacID == id
                state.pairedMacs.remove(id: id)
                state.connectionStatuses[id] = nil
                if state.pairedMacs.isEmpty {
                    state.selectedMacID = nil
                    state.catalog = []
                    state.catalogRevision = 0
                    state.selectedControlIDs = []
                    state.order = []
                    return .send(.delegate(.allMacsRemoved))
                }
                guard wasSelected, let fallback = state.pairedMacs.first else {
                    return .send(.delegate(.macForgotten(id)))
                }
                return .concatenate(
                    .send(.delegate(.macForgotten(id))),
                    .send(.selectedMacChanged(fallback.id))
                )

            case .management(.dismiss):
                return .none

            case let .foregroundChanged(isForegrounded):
                var effects: [Effect<Action>] = []
                if state.pairing != nil {
                    effects.append(.send(.pairing(.presented(.foregroundChanged(isForegrounded)))))
                }
                if isForegrounded == false {
                    state.isObservingConnectionEvents = false
                    effects.append(.cancel(id: CancelID.selectedMacLoad))
                    effects.append(.cancel(id: CancelID.connectionEvents))
                } else if state.isObservingConnectionEvents == false {
                    effects.append(.send(.task))
                }
                return .merge(effects)

            case .pairing, .management, .delegate:
                return .none
            }
        }
        .ifLet(\.$pairing, action: \.pairing) { PairingFeature() }
        .ifLet(\.$management, action: \.management) { MacManagementFeature() }
    }

    private func observeConnectionEvents() -> Effect<Action> {
        .run { [connection] send in
            for await event in connection.events() {
                try Task.checkCancellation()
                await send(.connectionEvent(event))
            }
            await send(.connectionEventsFinished)
        } catch: { _, send in
            await send(.connectionEventsFinished)
        }
        .cancellable(id: CancelID.connectionEvents, cancelInFlight: true)
    }

    private func loadSelectedMac(id: UUID, generation: UInt64) -> Effect<Action> {
        .run { [persistence] send in
            async let layout = persistence.loadLayout(id)
            async let cache = persistence.loadCatalog(id)
            let values = try await (layout, cache)
            await send(.selectedMacDataLoaded(generation, id, values.0, values.1))
        } catch: { _, send in
            await send(.selectedMacDataLoaded(generation, id, nil, nil))
        }
        .cancellable(id: CancelID.selectedMacLoad, cancelInFlight: true)
    }

    private func handleConnectionEvent(_ event: RemoteConnectionEvent, state: inout State) -> Effect<Action> {
        switch event {
        case let .connecting(id):
            state.connectionStatuses[id] = .connecting
        case let .authenticated(id):
            state.connectionStatuses[id] = .connected
            if var mac = state.pairedMacs[id: id] {
                mac.requiresPairing = false
                mac.lastConnectedAt = Date()
                state.pairedMacs[id: id] = mac
            }
        case let .offline(id, reason):
            state.connectionStatuses[id] = .offline(reason)
        case let .revoked(id):
            state.connectionStatuses[id] = .needsPairing
            if var mac = state.pairedMacs[id: id] { mac.requiresPairing = true; state.pairedMacs[id: id] = mac }
        case let .catalog(id, revision, controls):
            guard id == state.selectedMacID else { return .none }
            if controls.isEmpty, revision > state.catalogRevision { return .none }
            guard revision >= state.catalogRevision else { return .none }
            state.catalogRevision = revision
            state.catalog = IdentifiedArray(uniqueElements: controls)
            return .run { [persistence] send in
                do {
                    try await persistence.saveCatalog(id, revision, controls)
                    await send(.catalogCacheSaveResponse(id, revision, .success))
                } catch {
                    await send(.catalogCacheSaveResponse(id, revision, .failure))
                }
            }
        case .status, .action:
            break
        }
        return .none
    }

    private func enqueueLayoutSave(macID: UUID, state: inout State) -> Effect<Action> {
        let layout = currentLayout(macID: macID, state: state)
        state.pendingLayoutSaves[macID] = layout
        guard state.layoutSaveInFlight.contains(macID) == false else { return .none }
        return startLayoutSave(layout, state: &state)
    }

    private func startLayoutSave(_ layout: MacDashboardLayout, state: inout State) -> Effect<Action> {
        let macID = layout.macID
        state.layoutSaveGenerations[macID, default: 0] &+= 1
        let generation = state.layoutSaveGenerations[macID] ?? 0
        state.layoutSaveInFlight.insert(macID)
        return .run { [persistence] send in
            do {
                try await persistence.saveLayout(layout)
                await send(.layoutSaveResponse(macID, generation, layout, .success))
            } catch {
                await send(.layoutSaveResponse(macID, generation, layout, .failure))
            }
        }
    }

    private func currentLayout(macID: UUID, state: State) -> MacDashboardLayout {
        .init(macID: macID, selectedControlIDs: state.selectedControlIDs, order: state.order)
    }

    private func moving<T>(_ values: [T], from source: IndexSet, to destination: Int) -> [T] {
        let moved = source.sorted().map { values[$0] }
        var result = values.enumerated().filter { source.contains($0.offset) == false }.map(\.element)
        let removedBeforeDestination = source.filter { $0 < destination }.count
        result.insert(contentsOf: moved, at: max(0, min(result.count, destination - removedBeforeDestination)))
        return result
    }
}
