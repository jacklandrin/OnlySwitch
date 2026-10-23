#if os(macOS)
import Foundation
import Testing
import ComposableArchitecture
@testable import XcodeCleaner

@MainActor
struct XcodeCleanerFeatureTests {
    let generation = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let cache = CleanerItem(id: "derivedData", category: .derivedData, title: "DerivedData", bytes: 20)
    let device = CleanerItem(id: "device:test", category: .simulatorDevice, title: "Phone", bytes: nil, requiresConfirmation: true)

    @Test func scanUsesInjectedClientAndDisplaysSnapshot() async {
        let snapshot = CleanerSnapshot(items: [cache])
        let store = TestStore(initialState: XcodeCleanerFeature.State()) { XcodeCleanerFeature() } withDependencies: {
            $0.uuid = .constant(generation)
            $0.xcodeCleanerClient.scan = { snapshot }
        }
        store.exhaustivity = .off
        await store.send(.scanTapped)
        #expect(store.state.activity == .scanning)
        await store.receive(\.scanResponse)
        #expect(store.state.activity == .idle)
        #expect(store.state.snapshot == snapshot)
        #expect(!store.state.isStale)
    }

    @Test func staleAndNonownerDialogCallbacksCannotConfirmOrDismissAnotherRequest() async {
        let owner = UUID(), other = UUID()
        var initial = XcodeCleanerFeature.State()
        initial.activeHosts = [owner, other]
        initial.snapshot = CleanerSnapshot(items: [device])
        initial.confirmationHostID = owner
        initial.confirmationItemID = device.id
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() }
        await store.send(.confirmCleanupInHost(itemID: device.id, hostID: other))
        await store.send(.cancelConfirmationInHost(itemID: device.id, hostID: other))
        await store.send(.confirmCleanupInHost(itemID: "old-item", hostID: owner))
        await store.send(.cancelConfirmationInHost(itemID: "old-item", hostID: owner))
        #expect(store.state.confirmationItemID == device.id)
        #expect(store.state.activity == .idle)
    }

    @Test func oldResponseCannotOverwriteNewerScan() async {
        var initial = XcodeCleanerFeature.State()
        initial.scanGeneration = generation
        initial.activity = .scanning
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() }
        let old = CleanerSnapshot(items: [cache])
        await store.send(.scanResponse(generation: UUID(), result: .success(old)))
        #expect(store.state.snapshot == nil)
        #expect(store.state.activity == .scanning)
    }

    @Test func scanFailurePreservesSnapshotAndMarksItStale() async {
        let snapshot = CleanerSnapshot(items: [cache])
        let failure = CleanerFailure(key: "Xcode Cleaner Scan Failed")
        var initial = XcodeCleanerFeature.State()
        initial.snapshot = snapshot
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() } withDependencies: {
            $0.uuid = .constant(generation)
            $0.xcodeCleanerClient.scan = { throw failure }
        }
        store.exhaustivity = .off
        await store.send(.scanTapped)
        await store.receive(\.scanResponse)
        #expect(store.state.snapshot == snapshot)
        #expect(store.state.isStale)
        #expect(store.state.error == failure)
    }

    @Test func destructiveItemRequiresConfirmationAndCancelDoesNotClean() async {
        var initial = XcodeCleanerFeature.State()
        initial.snapshot = CleanerSnapshot(items: [device])
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() }
        store.exhaustivity = .off
        await store.send(.cleanTapped(itemID: device.id))
        #expect(store.state.confirmationItemID == device.id)
        #expect(store.state.activity == .idle)
        await store.send(.cancelConfirmationTapped)
        #expect(store.state.confirmationItemID == nil)
        await store.finish()
    }

    @Test func unknownItemAndBusyStateNeverStartCleanup() async {
        var initial = XcodeCleanerFeature.State()
        initial.snapshot = CleanerSnapshot(items: [cache])
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() }
        await store.send(.cleanTapped(itemID: "unknown"))
        var busy = initial
        busy.activity = .cleaning(cache.id)
        let busyStore = TestStore(initialState: busy) { XcodeCleanerFeature() }
        await busyStore.send(.cleanTapped(itemID: cache.id))
        await busyStore.send(.scanTapped)
        #expect(busyStore.state.activity == .cleaning(cache.id))
    }

    @Test func unknownSizesAreSeparateFromKnownTotal() {
        let snapshot = CleanerSnapshot(items: [cache, device])
        #expect(snapshot.knownBytes == 20)
        #expect(snapshot.hasUnknownBytes)
    }

    @Test func sharedScanSurvivesOneHostDisappearingAndCancelsWhenLastHostLeaves() async {
        let first = UUID(), second = UUID()
        var initial = XcodeCleanerFeature.State()
        initial.activeHosts = [first, second]
        initial.activity = .scanning
        initial.scanGeneration = generation
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() }
        store.exhaustivity = .off
        await store.send(.hostDisappeared(first))
        #expect(store.state.activeHosts == [second])
        #expect(store.state.activity == .scanning)
        #expect(store.state.scanGeneration == generation)
        await store.send(.hostDisappeared(second))
        #expect(store.state.activeHosts.isEmpty)
        #expect(store.state.activity == .idle)
        #expect(store.state.scanGeneration == nil)
    }

    @Test func destructiveConfirmationBelongsToInitiatingHostAndDismissesWithIt() async {
        let host = UUID(), otherHost = UUID()
        var initial = XcodeCleanerFeature.State()
        initial.activeHosts = [host, otherHost]
        initial.snapshot = CleanerSnapshot(items: [device])
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() }
        store.exhaustivity = .off
        await store.send(.cleanTappedInHost(itemID: device.id, hostID: host))
        #expect(store.state.confirmationHostID == host)
        #expect(store.state.confirmationItemID == device.id)
        await store.send(.hostDisappeared(host))
        #expect(store.state.confirmationHostID == nil)
        #expect(store.state.confirmationItemID == nil)
        #expect(store.state.activeHosts == [otherHost])
    }

    @Test func cancellingScanInvalidatesItsLateResponse() async {
        var initial = XcodeCleanerFeature.State()
        initial.scanGeneration = generation
        initial.activity = .scanning
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() }
        store.exhaustivity = .off
        await store.send(.cancelScanTapped)
        #expect(store.state.activity == .idle)
        #expect(store.state.scanGeneration == nil)
        await store.send(.scanResponse(generation: generation, result: .success(CleanerSnapshot(items: [cache]))))
        #expect(store.state.snapshot == nil)
    }

    @Test func confirmingCleanupPassesExactRequestAndRefreshesInventory() async {
        let snapshot = CleanerSnapshot(items: [device])
        let refreshed = CleanerSnapshot(items: [])
        let outcome = CleanerCleanupResult(removedItemIDs: [device.id], confirmedBytes: nil)
        let recorder = CleanerRequestRecorder()
        var initial = XcodeCleanerFeature.State()
        initial.snapshot = snapshot
        initial.activeHosts = [UUID()]
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() } withDependencies: {
            $0.uuid = .constant(generation)
            $0.xcodeCleanerClient.clean = { request in
                await recorder.record(request)
                return outcome
            }
            $0.xcodeCleanerClient.scan = { refreshed }
        }
        store.exhaustivity = .off
        await store.send(.cleanTapped(itemID: device.id))
        #expect(await recorder.requests.isEmpty)
        await store.send(.confirmCleanupTapped)
        await store.receive(\.cleanupResponse)
        #expect(await recorder.requests == [CleanerCleanupRequest(snapshotID: snapshot.id, itemIDs: [device.id])])
        await store.receive(\.refreshResponse)
        #expect(store.state.snapshot == refreshed)
        #expect(store.state.lastCleanupResult == outcome)
        #expect(store.state.activity == .idle)
    }

    @Test func partialCleanupRefreshesBytesAndPreservesFailures() async {
        let failure = CleanerFailure(key: "Xcode Cleaner Remove Failed")
        let outcome = CleanerCleanupResult(failures: [failure])
        let refreshed = CleanerSnapshot(items: [])
        var initial = XcodeCleanerFeature.State()
        initial.snapshot = CleanerSnapshot(items: [cache])
        initial.activeHosts = [UUID()]
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() } withDependencies: {
            $0.uuid = .constant(generation)
            $0.xcodeCleanerClient.clean = { _ in outcome }
            $0.xcodeCleanerClient.scan = { refreshed }
        }
        store.exhaustivity = .off
        await store.send(.cleanTapped(itemID: cache.id))
        await store.receive(\.cleanupResponse)
        await store.receive(\.refreshResponse)
        #expect(store.state.snapshot == refreshed)
        #expect(store.state.lastCleanupResult == outcome)
    }

    @Test func cleanupFailurePreservesInventoryAndAllowsRetry() async {
        let snapshot = CleanerSnapshot(items: [cache])
        let failure = CleanerFailure(key: "Xcode Cleaner Cleanup Failed")
        let recorder = CleanerRequestRecorder()
        var initial = XcodeCleanerFeature.State()
        initial.snapshot = snapshot
        let store = TestStore(initialState: initial) { XcodeCleanerFeature() } withDependencies: {
            $0.uuid = .constant(generation)
            $0.xcodeCleanerClient.clean = { request in
                await recorder.record(request)
                throw failure
            }
        }
        store.exhaustivity = .off
        await store.send(.cleanTapped(itemID: cache.id))
        await store.receive(\.cleanupResponse)
        #expect(store.state.activity == .idle)
        #expect(store.state.error == failure)
        #expect(store.state.snapshot == snapshot)
        await store.send(.cleanTapped(itemID: cache.id))
        await store.receive(\.cleanupResponse)
        #expect(await recorder.requests.count == 2)
    }
}

private actor CleanerRequestRecorder {
    var requests: [CleanerCleanupRequest] = []
    func record(_ request: CleanerCleanupRequest) { requests.append(request) }
}
#endif
