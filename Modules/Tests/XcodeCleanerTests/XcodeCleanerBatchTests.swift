#if os(macOS)
import Foundation
import Testing
import ComposableArchitecture
@testable import XcodeCleaner

actor CleanerAsyncGate<Value: Sendable> {
    private var continuations: [CheckedContinuation<Value, Never>] = []
    private var result: Value?
    private var requested = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    func value() async -> Value {
        requested = true
        observers.forEach { $0.resume() }; observers.removeAll()
        if let result { return result }
        return await withCheckedContinuation { continuations.append($0) }
    }
    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func resolve(_ value: Value) { result = value; continuations.forEach { $0.resume(returning: value) }; continuations.removeAll() }
}

actor CleanerBatchRecorder {
    var requests: [CleanerCleanupRequest] = []
    var measurements = 0
    func record(_ request: CleanerCleanupRequest) { requests.append(request) }
    func measure() { measurements += 1 }
}

@MainActor
struct XcodeCleanerBatchTests {
    let host = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let cache = CleanerItem(id: "cache:a", category: .derivedData, title: "Build", bytes: 20)
    let other = CleanerItem(id: "cache:b", category: .spmCaches, title: "Packages", bytes: 30)
    let device = CleanerItem(id: "device:a", category: .simulatorDevice, title: "Phone", bytes: nil, requiresConfirmation: true)
    func state(_ items: [CleanerItem]) -> XcodeCleanerFeature.State {
        var state = XcodeCleanerFeature.State()
        state.snapshot = CleanerSnapshot(items: items)
        state.activeHosts = [host]
        return state
    }

    @Test func selectionDeduplicatesAndExcludesMissingAndDisabledItems() async {
        var disabled = other; disabled.canClean = false
        let store = TestStore(initialState: state([cache, disabled, device])) { XcodeCleanerFeature() }
        store.exhaustivity = .off
        await store.send(.selectionChanged(itemID: cache.id, isSelected: true))
        await store.send(.selectionChanged(itemID: cache.id, isSelected: true))
        await store.send(.selectionChanged(itemID: disabled.id, isSelected: true))
        await store.send(.selectionChanged(itemID: "unknown", isSelected: true))
        #expect(store.state.selectedItemIDs == [cache.id])
        await store.send(.selectAllTapped)
        #expect(store.state.selectedItemIDs == [cache.id, device.id])
        await store.send(.clearSelectionTapped)
        #expect(store.state.selectedItemIDs.isEmpty)
    }

    @Test func batchConfirmationFreezesRequestAndRejectsWrongHostAndOldToken() async throws {
        let recorder = CleanerBatchRecorder()
        var initial = state([cache, device, other])
        initial.selectedItemIDs = [cache.id, device.id]
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() } withDependencies: {
            $0.xcodeCleanerClient.clean = { request in await recorder.record(request); throw CleanerFailure(key: "test") }
        }
        store.exhaustivity = .off
        await store.send(.cleanSelectedInHost(host))
        let pending = try #require(store.state.pendingConfirmation)
        #expect(pending.itemIDs == [cache.id, device.id])
        #expect(pending.snapshotID == initial.snapshot?.id)
        #expect(pending.hostID == host)
        await store.send(.selectionChanged(itemID: other.id, isSelected: true))
        await store.send(.confirmBatch(token: pending.token, hostID: UUID()))
        await store.send(.confirmBatch(token: UUID(), hostID: host))
        #expect(await recorder.requests.isEmpty)
        await store.send(.confirmBatch(token: pending.token, hostID: host))
        await store.receive(\.cleanupResponse)
        #expect(await recorder.requests == [.init(snapshotID: pending.snapshotID, itemIDs: [cache.id, device.id])])
    }

    @Test func partialBatchRemovesOnlyConfirmedRequestedRowsBeforeRefreshFinishes() async throws {
        let gate = CleanerAsyncGate<CleanerSnapshot>()
        let recorder = CleanerBatchRecorder()
        var initial = state([cache, other, device]); initial.selectedItemIDs = [cache.id, other.id]
        let result = CleanerCleanupResult(removedItemIDs: [cache.id, device.id], failures: [.init(key: "partial", itemID: other.id, mayHaveRemovedContents: true)])
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() } withDependencies: {
            $0.xcodeCleanerClient.clean = { request in await recorder.record(request); return result }
            $0.xcodeCleanerClient.scan = { await gate.value() }
        }
        store.exhaustivity = .off
        await store.send(.cleanSelectedInHost(host))
        await store.receive(\.cleanupResponse)
        await gate.waitUntilRequested()
        #expect(store.state.snapshot?.items.map(\.id) == [other.id, device.id])
        #expect(store.state.snapshot?.items.first?.bytes == nil)
        #expect(store.state.selectedItemIDs == [other.id])
        #expect(store.state.activity == .idle)
        #expect(store.state.isRefreshing)
        #expect(store.state.isEstimated)
        #expect(!store.state.isStale)
        #expect(await recorder.requests.count == 1)
        await gate.resolve(CleanerSnapshot(items: [other, device]))
        await store.receive(\.refreshResponse)
        #expect(!store.state.isRefreshing)
    }

    @Test func nextBatchStartsDuringHeldRefreshAndLateRefreshCannotResurrectRows() async throws {
        let gate = CleanerAsyncGate<CleanerSnapshot>()
        let recorder = CleanerBatchRecorder()
        let initial = state([cache, other])
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() } withDependencies: {
            $0.xcodeCleanerClient.clean = { request in await recorder.record(request); return .init(removedItemIDs: request.itemIDs) }
            $0.xcodeCleanerClient.scan = { await gate.value() }
        }
        store.exhaustivity = .off
        await store.send(.cleanTapped(itemID: cache.id))
        await store.receive(\.cleanupResponse)
        await gate.waitUntilRequested()
        let oldGeneration = try #require(store.state.refreshGeneration)
        let oldRevision = store.state.inventoryRevision
        await store.send(.cleanTapped(itemID: other.id))
        await store.receive(\.cleanupResponse)
        #expect(await recorder.requests.map(\.snapshotID) == [initial.snapshot!.id, initial.snapshot!.id])
        #expect(store.state.snapshot?.items.isEmpty == true)
        await store.send(.refreshResponse(generation: oldGeneration, revision: oldRevision, result: .success(initial.snapshot!)))
        #expect(store.state.snapshot?.items.isEmpty == true)
        await gate.resolve(CleanerSnapshot())
        await store.receive(\.refreshResponse)
    }

    @Test func backgroundFailurePreservesUsableEstimatedInventory() async {
        let initial = state([cache, other])
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() } withDependencies: {
            $0.xcodeCleanerClient.clean = { request in .init(removedItemIDs: request.itemIDs) }
            $0.xcodeCleanerClient.scan = { throw CleanerFailure(key: "refresh unavailable") }
        }
        store.exhaustivity = .off
        await store.send(.cleanTapped(itemID: cache.id))
        await store.receive(\.cleanupResponse)
        await store.receive(\.refreshResponse)
        #expect(store.state.snapshot?.items == [other])
        #expect(store.state.snapshot?.knownBytes == 30)
        #expect(store.state.isEstimated)
        #expect(!store.state.isStale)
        #expect(store.state.activity == .idle)
        await store.send(.selectionChanged(itemID: other.id, isSelected: true))
        #expect(store.state.selectedItemIDs == [other.id])
    }

    @Test func automaticRefreshSuppressesCleanedEmptyRowsButManualScanRestoresThem() async {
        var empty = cache; empty.bytes = 0
        let refreshed = CleanerSnapshot(items: [empty, other])
        let store = TestStore(initialState: state([cache, other])) { XcodeCleanerFeature() } withDependencies: {
            $0.xcodeCleanerClient.clean = { request in .init(removedItemIDs: request.itemIDs) }
            $0.xcodeCleanerClient.scan = { refreshed }
        }
        store.exhaustivity = .off
        await store.send(.cleanTapped(itemID: cache.id))
        await store.receive(\.cleanupResponse)
        await store.receive(\.refreshResponse)
        #expect(store.state.snapshot?.items == [other])
        await store.send(.scanTapped)
        await store.receive(\.scanResponse)
        #expect(store.state.snapshot?.items == [empty, other])
        #expect(!store.state.isEstimated)
    }

    @Test func lateAndDuplicateCleanupResponsesCannotRemoveRows() async {
        let initial = state([cache, other])
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() }
        await store.send(.cleanupResponse(generation: UUID(), result: .success(.init(removedItemIDs: [cache.id]))))
        #expect(store.state.snapshot == initial.snapshot)
    }

    @Test func regeneratedNonemptyCacheReturnsDuringAutomaticRefresh() async {
        var regenerated = cache; regenerated.bytes = 9
        let refreshed = CleanerSnapshot(items: [regenerated, other])
        let store = TestStore(initialState: state([cache, other])) { XcodeCleanerFeature() } withDependencies: {
            $0.xcodeCleanerClient.clean = { request in .init(removedItemIDs: request.itemIDs) }
            $0.xcodeCleanerClient.scan = { refreshed }
        }
        store.exhaustivity = .off
        await store.send(.cleanTapped(itemID: cache.id))
        await store.receive(\.cleanupResponse)
        await store.receive(\.refreshResponse)
        #expect(store.state.snapshot?.items == [regenerated, other])
        #expect(store.state.snapshot?.knownBytes == 39)
        #expect(!store.state.isEstimated)
    }

    @Test func partialBackgroundInventoryPreservesUsableEstimateAndAuthorization() async {
        let initial = state([cache, other])
        let partial = CleanerSnapshot(items: [], failures: [.init(key: "read denied", itemID: other.id)])
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() } withDependencies: {
            $0.xcodeCleanerClient.clean = { request in .init(removedItemIDs: request.itemIDs) }
            $0.xcodeCleanerClient.scan = { partial }
        }
        store.exhaustivity = .off
        await store.send(.cleanTapped(itemID: cache.id))
        await store.receive(\.cleanupResponse)
        await store.receive(\.refreshResponse)
        #expect(store.state.snapshot?.id == initial.snapshot?.id)
        #expect(store.state.snapshot?.items == [other])
        #expect(store.state.snapshot?.knownBytes == 30)
        #expect(store.state.isEstimated)
        #expect(!store.state.isStale)
        #expect(store.state.refreshError != nil)
        await store.send(.selectionChanged(itemID: other.id, isSelected: true))
        #expect(store.state.selectedItemIDs == [other.id])
    }

    @Test func unscopedPartialFailureMakesOnlyRequestedRowsUnknown() async {
        let gate = CleanerAsyncGate<CleanerSnapshot>()
        let initial = state([cache, other])
        let outcome = CleanerCleanupResult(failures: [.init(key: "partial", mayHaveRemovedContents: true)])
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() } withDependencies: {
            $0.xcodeCleanerClient.clean = { _ in outcome }
            $0.xcodeCleanerClient.scan = { await gate.value() }
        }
        store.exhaustivity = .off
        await store.send(.cleanTapped(itemID: cache.id))
        await store.receive(\.cleanupResponse)
        await gate.waitUntilRequested()
        #expect(store.state.snapshot?.items.first { $0.id == cache.id }?.bytes == nil)
        #expect(store.state.snapshot?.items.first { $0.id == other.id }?.bytes == 30)
        await gate.resolve(initial.snapshot!)
        await store.receive(\.refreshResponse)
    }

    @Test func cleanupFinishingAfterLastHostLeavesDefersRefreshUntilReopening() async {
        let cleanup = CleanerAsyncGate<CleanerCleanupResult>()
        let scan = CleanerAsyncGate<CleanerSnapshot>()
        let store = TestStore(initialState: state([cache, other])) { XcodeCleanerFeature() } withDependencies: {
            $0.xcodeCleanerClient.clean = { _ in await cleanup.value() }
            $0.xcodeCleanerClient.scan = { await scan.value() }
        }
        store.exhaustivity = .off
        await store.send(.cleanTapped(itemID: cache.id))
        await cleanup.waitUntilRequested()
        await store.send(.hostDisappeared(host))
        await cleanup.resolve(.init(removedItemIDs: [cache.id]))
        await store.receive(\.cleanupResponse)
        #expect(store.state.snapshot?.items == [other])
        #expect(store.state.isEstimated)
        #expect(store.state.activity == .idle)
        #expect(!store.state.isRefreshing)
        #expect(store.state.refreshGeneration == nil)
        await store.send(.hostAppeared(host))
        await scan.waitUntilRequested()
        #expect(store.state.isRefreshing)
        #expect(store.state.activity == .idle)
        await scan.resolve(CleanerSnapshot(items: [other]))
        await store.receive(\.refreshResponse)
        #expect(!store.state.isEstimated)
    }
}
#endif
