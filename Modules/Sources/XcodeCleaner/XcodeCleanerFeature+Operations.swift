#if os(macOS)
import Foundation
import ComposableArchitecture

extension XcodeCleanerFeature {
    func clearConfirmation(_ state: inout State) {
        state.pendingConfirmation = nil; state.confirmationItemID = nil; state.confirmationHostID = nil
    }
    func accept(_ state: inout State, snapshot: CleanerSnapshot) {
        state.snapshot = snapshot; state.isStale = false; state.isEstimated = false; state.refreshError = nil
        let eligible = Set(snapshot.items.filter(\.canClean).map(\.id))
        state.selectedItemIDs.formIntersection(eligible)
        clearConfirmation(&state)
    }
    func activate(_ id: UUID) -> Effect<Action> { .run { [client] _ in await client.activateSnapshot(id) } }
    func cancelScan(_ state: inout State) -> Effect<Action> {
        state.activity = .idle; state.scanGeneration = nil; state.isStale = state.snapshot != nil
        return .cancel(id: CancelID.scan)
    }
    func cancelRefresh(_ state: inout State) -> Effect<Action> {
        state.isRefreshing = false; state.refreshGeneration = nil
        return .cancel(id: CancelID.refresh)
    }
    func beginCleanup(_ state: inout State, ids: [String], hostID: UUID?) -> Effect<Action> {
        guard state.activity == .idle, !state.isStale, let snapshot = state.snapshot, !ids.isEmpty else { return .none }
        let ordered = snapshot.items.filter { ids.contains($0.id) && $0.canClean }.map(\.id)
        guard !ordered.isEmpty else { return .none }
        if snapshot.items.contains(where: { ordered.contains($0.id) && $0.requiresConfirmation }) {
            let pending = CleanerBatchConfirmation(token: uuid(), hostID: hostID ?? Self.legacyHost, snapshotID: snapshot.id, itemIDs: ordered)
            state.pendingConfirmation = pending; state.confirmationItemID = ordered.first; state.confirmationHostID = hostID
            return .none
        }
        return clean(&state, request: .init(snapshotID: snapshot.id, itemIDs: ordered))
    }
    func scan(_ state: inout State) -> Effect<Action> {
        let canceledRefresh = cancelRefresh(&state), generation = uuid()
        state.activity = .scanning; state.scanGeneration = generation; state.error = nil
        state.suppressedEmptyIDs = []; clearConfirmation(&state)
        let effect: Effect<Action> = .run { [client] send in
            do {
                let snapshot = try await client.scan()
                try Task.checkCancellation()
                await send(.scanResponse(generation: generation, result: .success(snapshot)))
            } catch is CancellationError {}
            catch { await send(.scanResponse(generation: generation, result: .failure(.wrapping(error)))) }
        }.cancellable(id: CancelID.scan, cancelInFlight: true)
        return .merge(canceledRefresh, effect)
    }
    func refresh(_ state: inout State) -> Effect<Action> {
        let generation = uuid(), revision = state.inventoryRevision
        state.isRefreshing = true; state.refreshGeneration = generation; state.refreshError = nil
        return .run { [client] send in
            do {
                let snapshot = try await client.scan()
                try Task.checkCancellation()
                await send(.refreshResponse(generation: generation, revision: revision, result: .success(snapshot)))
            } catch is CancellationError {}
            catch { await send(.refreshResponse(generation: generation, revision: revision, result: .failure(.wrapping(error)))) }
        }.cancellable(id: CancelID.refresh, cancelInFlight: true)
    }
    func clean(_ state: inout State, request: CleanerCleanupRequest) -> Effect<Action> {
        guard state.activity == .idle, !state.isStale, state.snapshot?.id == request.snapshotID,
              !request.itemIDs.isEmpty, request.itemIDs.allSatisfy({ id in state.snapshot?.items.contains(where: { $0.id == id && $0.canClean }) == true }) else { return .none }
        let canceledRefresh = cancelRefresh(&state), generation = uuid()
        state.inventoryRevision += 1
        state.cleanupGeneration = generation; state.cleaningItemIDs = Set(request.itemIDs)
        state.activity = .cleaning(request.itemIDs[0]); state.error = nil; state.lastCleanupResult = nil
        clearConfirmation(&state)
        let operation: Effect<Action> = .run { [client] send in
            do { await send(.cleanupResponse(generation: generation, result: .success(try await client.clean(request)))) }
            catch { await send(.cleanupResponse(generation: generation, result: .failure(.wrapping(error)))) }
        }
        // Finish cancellation before any destructive work begins; authorization is independently immutable.
        return .concatenate(canceledRefresh, operation)
    }
    func reconcileCleanup(_ state: inout State, requested: Set<String>, outcome: CleanerCleanupResult) {
        let failures = outcome.failures.filter { $0.itemID == nil || requested.contains($0.itemID!) }
        let failedIDs = Set(failures.compactMap(\.itemID))
        let removed = Set(outcome.removedItemIDs).intersection(requested).subtracting(failedIDs)
        state.snapshot?.items.removeAll { removed.contains($0.id) }
        for index in state.snapshot?.items.indices ?? 0..<0 {
            let id = state.snapshot!.items[index].id
            if requested.contains(id), failures.contains(where: { ($0.itemID == id || $0.itemID == nil) && $0.mayHaveRemovedContents }) { state.snapshot?.items[index].bytes = nil }
        }
        state.selectedItemIDs.subtract(removed)
        state.selectedItemIDs.formUnion(failedIDs)
        state.suppressedEmptyIDs.formUnion(removed)
        state.lastCleanupResult = .init(removedItemIDs: outcome.removedItemIDs.filter { removed.contains($0) }, confirmedBytes: outcome.confirmedBytes, failures: failures)
        state.isEstimated = true; state.isStale = false
    }
}
#endif
