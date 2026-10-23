#if os(macOS)
import Foundation
import ComposableArchitecture

@Reducer
public struct XcodeCleanerFeature {
    @ObservableState
    public struct State: Equatable {
        public var snapshot: CleanerSnapshot?
        public var activity: Activity = .idle
        public var scanGeneration: UUID?
        public var cleanupGeneration: UUID?
        public var confirmationItemID: String?
        public var confirmationHostID: UUID?
        public var activeHosts: Set<UUID> = []
        public var isStale = false
        public var error: CleanerFailure?
        public var lastCleanupResult: CleanerCleanupResult?
        public var selectedItemIDs: Set<String> = []
        public var cleaningItemIDs: Set<String> = []
        public var isRefreshing = false
        public var refreshGeneration: UUID?
        public var inventoryRevision = 0
        public var isEstimated = false
        public var pendingConfirmation: CleanerBatchConfirmation?
        public var refreshError: CleanerFailure?
        var suppressedEmptyIDs: Set<String> = []
        public init() {}
        public var confirmationItem: CleanerItem? { snapshot?.items.first { $0.id == confirmationItemID } }
        public var isBusy: Bool { activity != .idle }
        public var orderedSelectedIDs: [String] { snapshot?.items.filter { $0.canClean && selectedItemIDs.contains($0.id) }.map(\.id) ?? [] }
        public var confirmationItems: [CleanerItem] {
            guard let pendingConfirmation, pendingConfirmation.snapshotID == snapshot?.id else { return [] }
            return pendingConfirmation.itemIDs.compactMap { id in snapshot?.items.first { $0.id == id } }
        }
    }
    public enum Activity: Equatable, Sendable { case idle, scanning, cleaning(String) }
    public enum Action: Equatable, Sendable {
        case task, scanTapped, cancelScanTapped
        case hostAppeared(UUID), hostDisappeared(UUID)
        case cleanTappedInHost(itemID: String, hostID: UUID)
        case confirmCleanupInHost(itemID: String, hostID: UUID)
        case cancelConfirmationInHost(itemID: String, hostID: UUID)
        case scanResponse(generation: UUID, result: Result<CleanerSnapshot, CleanerFailure>)
        case cleanTapped(itemID: String), confirmCleanupTapped, cancelConfirmationTapped
        case cleanupResponse(generation: UUID, result: Result<CleanerCleanupResult, CleanerFailure>)
        case selectionChanged(itemID: String, isSelected: Bool), selectAllTapped, clearSelectionTapped
        case cleanSelectedInHost(UUID)
        case confirmBatch(token: UUID, hostID: UUID), cancelBatch(token: UUID, hostID: UUID)
        case refreshResponse(generation: UUID, revision: Int, result: Result<CleanerSnapshot, CleanerFailure>)
        case dismissError
    }
    @Dependency(\.xcodeCleanerClient) var client
    @Dependency(\.uuid) var uuid
    enum CancelID { case scan, refresh }
    static let legacyHost = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    public init() {}
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .hostAppeared(id):
                state.activeHosts.insert(id)
                if state.snapshot == nil, state.activity == .idle { return scan(&state) }
                if state.isEstimated, !state.isRefreshing, state.activity == .idle { return refresh(&state) }
                return .none
            case let .hostDisappeared(id):
                state.activeHosts.remove(id)
                if state.confirmationHostID == id { clearConfirmation(&state) }
                guard state.activeHosts.isEmpty else { return .none }
                let background = cancelRefresh(&state)
                if state.activity == .scanning { return .merge(cancelScan(&state), background) }
                return background
            case .task:
                guard state.snapshot == nil, state.activity == .idle else { return .none }
                return scan(&state)
            case .scanTapped:
                if case .cleaning = state.activity { return .none }
                return scan(&state)
            case .cancelScanTapped:
                guard state.activity == .scanning else { return .none }
                return cancelScan(&state)
            case let .scanResponse(generation, result):
                guard generation == state.scanGeneration else { return .none }
                state.activity = .idle; state.scanGeneration = nil
                switch result {
                case let .success(snapshot):
                    accept(&state, snapshot: snapshot)
                    return activate(snapshot.id)
                case let .failure(error): state.error = error; state.isStale = state.snapshot != nil
                }
                return .none
            case let .refreshResponse(generation, revision, result):
                guard generation == state.refreshGeneration, revision == state.inventoryRevision else { return .none }
                state.isRefreshing = false; state.refreshGeneration = nil
                switch result {
                case var .success(snapshot):
                    guard snapshot.failures.isEmpty else {
                        state.refreshError = .init(key: "Xcode Cleaner Refresh Failed", detail: snapshot.failures.compactMap(\.detail).joined(separator: "\n"))
                        return .none
                    }
                    snapshot.items.removeAll { state.suppressedEmptyIDs.contains($0.id) && $0.bytes == 0 && $0.category != .simulatorDevice && $0.category != .simulatorRuntime }
                    accept(&state, snapshot: snapshot)
                    return activate(snapshot.id)
                case let .failure(error):
                    state.refreshError = .init(key: "Xcode Cleaner Refresh Failed", detail: error.detail)
                }
                return .none
            case let .selectionChanged(id, selected):
                if !selected { state.selectedItemIDs.remove(id) }
                else if state.snapshot?.items.contains(where: { $0.id == id && $0.canClean }) == true { state.selectedItemIDs.insert(id) }
                return .none
            case .selectAllTapped:
                state.selectedItemIDs = Set(state.snapshot?.items.filter(\.canClean).map(\.id) ?? [])
                return .none
            case .clearSelectionTapped: state.selectedItemIDs = []; return .none
            case let .cleanSelectedInHost(host):
                guard state.activeHosts.contains(host) else { return .none }
                return beginCleanup(&state, ids: state.orderedSelectedIDs, hostID: host)
            case let .cleanTapped(id): return beginCleanup(&state, ids: [id], hostID: nil)
            case let .cleanTappedInHost(id, host):
                guard state.activeHosts.contains(host) else { return .none }
                return beginCleanup(&state, ids: [id], hostID: host)
            case let .confirmBatch(token, host):
                guard let pending = state.pendingConfirmation, pending.token == token, pending.hostID == host,
                      state.activeHosts.contains(host), pending.snapshotID == state.snapshot?.id else { return .none }
                clearConfirmation(&state)
                return clean(&state, request: .init(snapshotID: pending.snapshotID, itemIDs: pending.itemIDs))
            case let .cancelBatch(token, host):
                guard state.pendingConfirmation?.token == token, state.pendingConfirmation?.hostID == host else { return .none }
                clearConfirmation(&state); return .none
            case let .confirmCleanupInHost(id, host):
                guard state.confirmationItemID == id, state.confirmationHostID == host,
                      state.activeHosts.contains(host), let pending = state.pendingConfirmation,
                      pending.itemIDs == [id], pending.snapshotID == state.snapshot?.id else { return .none }
                clearConfirmation(&state)
                return clean(&state, request: .init(snapshotID: pending.snapshotID, itemIDs: pending.itemIDs))
            case let .cancelConfirmationInHost(id, host):
                guard state.confirmationItemID == id, state.confirmationHostID == host else { return .none }
                clearConfirmation(&state); return .none
            case .confirmCleanupTapped:
                guard let pending = state.pendingConfirmation, pending.snapshotID == state.snapshot?.id else { return .none }
                clearConfirmation(&state)
                return clean(&state, request: .init(snapshotID: pending.snapshotID, itemIDs: pending.itemIDs))
            case .cancelConfirmationTapped: clearConfirmation(&state); return .none
            case let .cleanupResponse(generation, result):
                guard generation == state.cleanupGeneration else { return .none }
                let requested = state.cleaningItemIDs
                state.activity = .idle; state.cleanupGeneration = nil; state.cleaningItemIDs = []
                switch result {
                case let .success(outcome):
                    reconcileCleanup(&state, requested: requested, outcome: outcome)
                    return state.activeHosts.isEmpty ? .none : refresh(&state)
                case let .failure(error): state.error = error
                }
                return .none
            case .dismissError: state.error = nil; return .none
            }
        }
    }
}
#endif
