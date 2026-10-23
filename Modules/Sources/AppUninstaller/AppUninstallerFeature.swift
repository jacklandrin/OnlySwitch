#if os(macOS)
import Foundation
import ComposableArchitecture

@Reducer
public struct AppUninstallerFeature {
    @ObservableState
    public struct State: Equatable {
        public var snapshot: UninstallerSnapshot?
        public var selectedItemIDs: Set<String> = []
        public var scanGeneration: UUID?
        public var removalGeneration: UUID?
        public var activeHosts: Set<UUID> = []
        public var pendingConfirmation: UninstallerConfirmation?
        public var error: UninstallerFailure?
        public var lastRemovalResult: UninstallerRemovalResult?
        public init() {}
        public var isBusy: Bool { scanGeneration != nil || removalGeneration != nil }
        public var orderedSelectedIDs: [String] { snapshot?.items.filter { selectedItemIDs.contains($0.id) }.map(\.id) ?? [] }
    }
    public enum Action: Equatable, Sendable {
        case applicationChosen(URL), chooseApplicationTapped, toggleSelection(String)
        case scanResponse(generation: UUID, result: Result<UninstallerSnapshot, UninstallerFailure>)
        case hostAppeared(UUID), hostDisappeared(UUID)
        case removeTapped(hostID: UUID), confirmRemoval(hostID: UUID, token: UUID), cancelConfirmation(hostID: UUID, token: UUID)
        case removalResponse(generation: UUID, result: Result<UninstallerRemovalResult, UninstallerFailure>)
        case openPrivacySettingsTapped, cancelScanTapped, selectAllTapped, clearSelectionTapped, invalidDrop
    }
    @Dependency(\.appUninstallerClient) var client
    @Dependency(\.uuid) var uuid
    private enum CancelID { case scan, chooser }
    public init() {}
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .chooseApplicationTapped:
                guard !state.isBusy else { return .none }
                return .run { [client] send in if let url = await client.chooseApplication() { await send(.applicationChosen(url)) } }.cancellable(id: CancelID.chooser, cancelInFlight: true)
            case let .applicationChosen(url):
                guard state.removalGeneration == nil else { return .none }
                let generation = uuid(); state.scanGeneration = generation; state.pendingConfirmation = nil; state.error = nil; state.lastRemovalResult = nil
                // A failed replacement scan must never leave an old app selected for removal.
                state.snapshot = nil; state.selectedItemIDs = []
                return .run { [client] send in
                    do { await send(.scanResponse(generation: generation, result: .success(try await client.scan(url)))) }
                    catch is CancellationError { }
                    catch { await send(.scanResponse(generation: generation, result: .failure((error as? UninstallerFailure) ?? .init(key: "App Uninstaller Scan Failed")))) }
                }.cancellable(id: CancelID.scan, cancelInFlight: true)
            case let .scanResponse(generation, result):
                guard generation == state.scanGeneration else { return .none }
                state.scanGeneration = nil
                switch result {
                case let .success(snapshot):
                    state.snapshot = snapshot; state.selectedItemIDs = Set(snapshot.items.map(\.id))
                    return .run { [client] _ in await client.activateSnapshot(snapshot.id) }
                case let .failure(failure): state.error = failure
                }
                return .none
            case let .hostAppeared(host): state.activeHosts.insert(host); return .none
            case let .hostDisappeared(host):
                state.activeHosts.remove(host)
                if state.pendingConfirmation?.hostID == host { state.pendingConfirmation = nil }
                guard state.activeHosts.isEmpty else { return .none }
                state.scanGeneration = nil
                return .merge(.cancel(id: CancelID.scan), .cancel(id: CancelID.chooser))
            case .cancelScanTapped: state.scanGeneration = nil; return .cancel(id: CancelID.scan)
            case let .toggleSelection(id):
                guard state.removalGeneration == nil, state.snapshot?.items.contains(where: { $0.id == id }) == true else { return .none }
                if !state.selectedItemIDs.insert(id).inserted { state.selectedItemIDs.remove(id) }
                return .none
            case .selectAllTapped:
                guard !state.isBusy else { return .none }
                state.selectedItemIDs = Set(state.snapshot?.items.map(\.id) ?? []); return .none
            case .clearSelectionTapped:
                guard !state.isBusy else { return .none }
                state.selectedItemIDs = []; return .none
            case let .removeTapped(host):
                guard !state.isBusy, state.pendingConfirmation == nil, state.activeHosts.contains(host), let snapshot = state.snapshot, !state.orderedSelectedIDs.isEmpty else { return .none }
                state.pendingConfirmation = .init(token: uuid(), hostID: host, snapshotID: snapshot.id, itemIDs: state.orderedSelectedIDs)
                return .none
            case let .cancelConfirmation(host, token):
                if state.pendingConfirmation?.hostID == host, state.pendingConfirmation?.token == token { state.pendingConfirmation = nil }
                return .none
            case let .confirmRemoval(host, token):
                guard !state.isBusy, let pending = state.pendingConfirmation, pending.token == token, pending.hostID == host, state.activeHosts.contains(host), state.snapshot?.id == pending.snapshotID else { return .none }
                state.pendingConfirmation = nil; state.error = nil
                let generation = uuid(); state.removalGeneration = generation
                return .run { [client] send in
                    do { await send(.removalResponse(generation: generation, result: .success(try await client.remove(.init(snapshotID: pending.snapshotID, itemIDs: pending.itemIDs))))) }
                    catch { await send(.removalResponse(generation: generation, result: .failure(.wrapping(error)))) }
                }
            case let .removalResponse(generation, result):
                guard state.removalGeneration == generation else { return .none }
                state.removalGeneration = nil
                switch result {
                case let .success(outcome):
                    state.lastRemovalResult = outcome
                    let removed = Set(outcome.removedItemIDs)
                    let removedApplication = state.snapshot?.items.contains { $0.kind == .application && removed.contains($0.id) } == true
                    if removedApplication {
                        // Unselected data is intentionally preserved. Once the bundle is gone,
                        // its old authorization cannot support another removal from this scan.
                        state.snapshot?.items = []; state.selectedItemIDs = []
                    } else {
                        state.snapshot?.items.removeAll { removed.contains($0.id) }; state.selectedItemIDs.subtract(removed)
                    }
                case let .failure(failure): state.error = failure
                }
                return .none
            case .openPrivacySettingsTapped: return .run { [client] _ in await client.openPrivacySettings() }
            case .invalidDrop: state.error = .init(key: "App Uninstaller Invalid App"); return .none
            }
        }
    }
}
#endif
