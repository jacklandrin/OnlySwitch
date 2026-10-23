#if os(macOS)
import Foundation
import Testing
import ComposableArchitecture
@testable import AppUninstaller

@MainActor
struct AppUninstallerFeatureTests {
    func initialState(host: UUID, snapshot: UninstallerSnapshot) -> AppUninstallerFeature.State {
        var state = AppUninstallerFeature.State()
        state.snapshot = snapshot
        state.selectedItemIDs = Set(snapshot.items.map(\.id))
        state.activeHosts = [host]
        return state
    }

    @Test func chooserCancellationDoesNotScanOrRemove() async {
        let store = TestStore(initialState: AppUninstallerFeature.State()) { AppUninstallerFeature() } withDependencies: {
            $0.appUninstallerClient.chooseApplication = { nil }
            $0.appUninstallerClient.scan = { _ in Issue.record("Cancelled picker scanned an app"); return uninstallerSnapshot() }
            $0.appUninstallerClient.remove = { _ in Issue.record("Cancelled picker removed files"); return .init(removedItemIDs: [], failures: []) }
        }
        store.exhaustivity = .off
        await store.send(.chooseApplicationTapped)
        await store.finish()
        #expect(store.state.snapshot == nil)
        #expect(store.state.scanGeneration == nil)
    }

    @Test func acceptedAppUsesClientAndSelectsDisplayedItems() async {
        let snapshot = uninstallerSnapshot(), recorder = UninstallerRequestRecorder()
        let store = TestStore(initialState: AppUninstallerFeature.State()) { AppUninstallerFeature() } withDependencies: {
            $0.appUninstallerClient.scan = { url in #expect(url == snapshot.applicationURL); return snapshot }
            $0.appUninstallerClient.activateSnapshot = { await recorder.activate($0) }
        }
        store.exhaustivity = .off
        await store.send(.applicationChosen(snapshot.applicationURL))
        await store.receive(\.scanResponse)
        await store.finish()
        #expect(store.state.snapshot == snapshot)
        #expect(store.state.selectedItemIDs == Set(snapshot.items.map(\.id)))
        #expect(await recorder.activations == [snapshot.id])
    }

    @Test func staleScanCannotReplaceSnapshotOrActivateAuthorization() async {
        let snapshot = uninstallerSnapshot(), recorder = UninstallerRequestRecorder()
        var state = AppUninstallerFeature.State(); state.scanGeneration = UUID()
        let store = TestStore(initialState: state) { AppUninstallerFeature() } withDependencies: {
            $0.appUninstallerClient.activateSnapshot = { await recorder.activate($0) }
        }
        await store.send(.scanResponse(generation: UUID(), result: .success(snapshot)))
        await store.finish()
        #expect(store.state.snapshot == nil)
        #expect(await recorder.activations.isEmpty)
    }

    @Test func pendingConfirmationRequiresExactOwnerAndTokenAndCancellationNeverRemoves() async throws {
        let host = UUID(), snapshot = uninstallerSnapshot(), recorder = UninstallerRequestRecorder()
        let store = TestStore(initialState: initialState(host: host, snapshot: snapshot)) { AppUninstallerFeature() } withDependencies: {
            $0.appUninstallerClient.remove = { request in await recorder.record(request); return .init(removedItemIDs: [], failures: []) }
        }
        store.exhaustivity = .off
        await store.send(.removeTapped(hostID: host))
        let pending = try #require(store.state.pendingConfirmation)
        #expect(await recorder.requests.isEmpty)
        await store.send(.confirmRemoval(hostID: UUID(), token: pending.token))
        await store.send(.confirmRemoval(hostID: host, token: UUID()))
        await store.send(.cancelConfirmation(hostID: UUID(), token: pending.token))
        #expect(store.state.pendingConfirmation == pending)
        await store.send(.cancelConfirmation(hostID: host, token: pending.token))
        await store.finish()
        #expect(store.state.pendingConfirmation == nil)
        #expect(await recorder.requests.isEmpty)
    }

    @Test func confirmedRemovalUsesFrozenOrderedSelectionAndRejectsDuplicateActions() async throws {
        let host = UUID(), snapshot = uninstallerSnapshot(), recorder = UninstallerRequestRecorder()
        let store = TestStore(initialState: initialState(host: host, snapshot: snapshot)) { AppUninstallerFeature() } withDependencies: {
            $0.appUninstallerClient.remove = { request in
                await recorder.record(request)
                return .init(removedItemIDs: request.itemIDs, failures: [])
            }
        }
        store.exhaustivity = .off
        await store.send(.removeTapped(hostID: host))
        let pending = try #require(store.state.pendingConfirmation)
        await store.send(.toggleSelection("preferences"))
        await store.send(.confirmRemoval(hostID: host, token: pending.token))
        await store.send(.confirmRemoval(hostID: host, token: pending.token))
        await store.receive(\.removalResponse)
        await store.finish()
        #expect(await recorder.requests == [.init(snapshotID: snapshot.id, itemIDs: snapshot.items.map(\.id))])
        #expect(store.state.snapshot?.items.isEmpty == true)
    }

    @Test func emptySelectionUnknownRowsAndAbsentHostsCannotConfirm() async {
        let host = UUID(), snapshot = uninstallerSnapshot()
        var state = initialState(host: host, snapshot: snapshot); state.selectedItemIDs = []
        let store = TestStore(initialState: state) { AppUninstallerFeature() }
        await store.send(.toggleSelection("unknown-path"))
        await store.send(.removeTapped(hostID: host))
        await store.send(.removeTapped(hostID: UUID()))
        #expect(store.state.pendingConfirmation == nil)
        #expect(store.state.selectedItemIDs.isEmpty)
    }

    @Test func lastHostDisappearanceCancelsScanAndInvalidatesLateResponse() async {
        let first = UUID(), second = UUID(), generation = UUID()
        var state = AppUninstallerFeature.State()
        state.activeHosts = [first, second]; state.scanGeneration = generation
        let store = TestStore(initialState: state) { AppUninstallerFeature() }
        store.exhaustivity = .off
        await store.send(.hostDisappeared(first))
        #expect(store.state.scanGeneration == generation)
        await store.send(.hostDisappeared(second))
        #expect(store.state.scanGeneration == nil)
        await store.send(.scanResponse(generation: generation, result: .success(uninstallerSnapshot())))
        #expect(store.state.snapshot == nil)
    }

    @Test func ownerDisappearanceDismissesItsPendingConfirmation() async {
        let host = UUID(), snapshot = uninstallerSnapshot()
        let store = TestStore(initialState: initialState(host: host, snapshot: snapshot)) { AppUninstallerFeature() }
        store.exhaustivity = .off
        await store.send(.removeTapped(hostID: host))
        #expect(store.state.pendingConfirmation != nil)
        await store.send(.hostDisappeared(host))
        #expect(store.state.pendingConfirmation == nil)
    }

    @Test func cancelledScanIgnoresLateResponse() async {
        let generation = UUID()
        var state = AppUninstallerFeature.State(); state.scanGeneration = generation
        let store = TestStore(initialState: state) { AppUninstallerFeature() }
        store.exhaustivity = .off
        await store.send(.cancelScanTapped)
        await store.send(.scanResponse(generation: generation, result: .success(uninstallerSnapshot())))
        #expect(store.state.scanGeneration == nil)
        #expect(store.state.snapshot == nil)
    }

    @Test func appOnlyRemovalFinishesWithoutOfferingUnselectedDataFromStaleScan() async throws {
        let host = UUID(), snapshot = uninstallerSnapshot(), recorder = UninstallerRequestRecorder()
        let store = TestStore(initialState: initialState(host: host, snapshot: snapshot)) { AppUninstallerFeature() } withDependencies: {
            $0.appUninstallerClient.remove = { request in
                await recorder.record(request)
                return .init(removedItemIDs: request.itemIDs)
            }
        }
        store.exhaustivity = .off
        await store.send(.toggleSelection("preferences"))
        await store.send(.removeTapped(hostID: host))
        let pending = try #require(store.state.pendingConfirmation)
        #expect(pending.itemIDs == ["app"])
        await store.send(.confirmRemoval(hostID: host, token: pending.token))
        await store.receive(\.removalResponse)
        await store.finish()
        #expect(await recorder.requests == [.init(snapshotID: snapshot.id, itemIDs: ["app"])])
        #expect(store.state.snapshot?.items.isEmpty == true)
        #expect(store.state.selectedItemIDs.isEmpty)
        await store.send(.removeTapped(hostID: host))
        #expect(store.state.pendingConfirmation == nil)
    }

    @Test func partialRemovalDropsSuccessAndKeepsFailedRowsSelected() async {
        let host = UUID(), snapshot = uninstallerSnapshot(), generation = UUID()
        var state = initialState(host: host, snapshot: snapshot); state.removalGeneration = generation
        let failure = UninstallerFailure(key: "App Uninstaller Remove Failed", itemID: "app")
        let store = TestStore(initialState: state) { AppUninstallerFeature() }
        store.exhaustivity = .off
        await store.send(.removalResponse(generation: UUID(), result: .success(.init(removedItemIDs: ["preferences"], failures: []))))
        #expect(store.state.snapshot == snapshot)
        await store.send(.removalResponse(generation: generation, result: .success(.init(removedItemIDs: ["preferences"], failures: [failure]))))
        #expect(store.state.snapshot?.items.map(\.id) == ["app"])
        #expect(store.state.selectedItemIDs == ["app"])
        #expect(store.state.removalGeneration == nil)
    }
}
#endif
