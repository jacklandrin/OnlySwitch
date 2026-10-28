#if os(macOS)
import ComposableArchitecture
import Foundation
import Testing
@testable import Tailscale

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TailscaleFeatureTests {
    @Test func cancellingAuthorizationWaitsForOwnedCommandThenRefreshes() async {
        let gate = TailscaleFeatureGate()
        let (waiting, signal) = AsyncStream<Void>.makeStream()
        defer { signal.finish() }
        let fresh = TailscaleFixtures.snapshot(accounts: [TailscaleFixtures.account("work")])
        var initial = TailscaleFeature.State()
        initial.snapshot = TailscaleFixtures.snapshot()
        initial.mutation = .login
        let store = TestStore(initialState: initial) { TailscaleFeature() } withDependencies: {
            $0.tailscaleClient.waitForIdle = { signal.yield(); await gate.wait() }
            $0.tailscaleClient.snapshot = { fresh }
        }
        store.exhaustivity = .off
        await store.send(.cancelLogin)
        for await _ in waiting { break }
        #expect(store.state.isCancellingAuthorization)
        #expect(store.state.snapshot == initial.snapshot)
        await store.send(.operationCompleted(0))
        #expect(store.state.snapshot == initial.snapshot)
        await gate.release()
        await store.receive(\.authorizationCancelled)
        await store.receive(\.snapshotResponse)
        #expect(store.state.snapshot == fresh)
        #expect(!store.state.isBusy)
        await store.finish()
    }

    @Test func disappearingCancelsAuthorizationAndIgnoresLateCompletion() async {
        var initial = TailscaleFeature.State()
        initial.snapshot = TailscaleFixtures.snapshot()
        initial.mutation = .forAccount("home", .renew)
        initial.generation = 4
        let store = TestStore(initialState: initial) { TailscaleFeature() }
        store.exhaustivity = .off
        await store.send(.disappeared)
        #expect(store.state.mutation == nil)
        #expect(store.state.generation == 5)
        await store.send(.operationCompleted(4))
        #expect(store.state.snapshot == initial.snapshot)
        #expect(!store.state.isLoading)
    }

    @Test func logoutRequiresConfirmationAndInvalidatesItAfterExternalAccountChange() async {
        let recorder = TailscaleOperationRecorder()
        var initial = TailscaleFeature.State()
        initial.snapshot = TailscaleFixtures.snapshot()
        initial.selectedAccountID = "home"
        let store = TestStore(initialState: initial) { TailscaleFeature() } withDependencies: {
            $0.tailscaleClient.perform = { await recorder.record($0) }
        }
        store.exhaustivity = .off
        await store.send(.confirmLogout)
        #expect(await recorder.operations.isEmpty)
        await store.send(.logout)
        #expect(store.state.logoutAccountID == "home")
        await store.send(.snapshotResponse(0, .success(TailscaleFixtures.snapshot(accounts: [TailscaleFixtures.account("work")]))))
        #expect(!store.state.logoutConfirmation)
        await store.send(.confirmLogout)
        #expect(await recorder.operations.isEmpty)
    }

    @Test func settingsPreferenceIntentCarriesTheDisplayedActiveAccount() async {
        let recorder = TailscaleOperationRecorder()
        let confirmed = TailscaleFixtures.snapshot()
        var initial = TailscaleFeature.State()
        initial.snapshot = confirmed
        let store = TestStore(initialState: initial) { TailscaleFeature() } withDependencies: {
            $0.tailscaleClient.perform = { await recorder.record($0) }
            $0.tailscaleClient.snapshot = { confirmed }
        }
        store.exhaustivity = .off
        await store.send(.preferenceChanged(.acceptDNS, false))
        await store.receive(\.operationCompleted)
        await store.receive(\.snapshotResponse)
        #expect(await recorder.operations == [.forAccount("home", .setPreference(.acceptDNS, false))])
        await store.finish()
    }
    @Test func failedRefreshRetainsTheLastConfirmedConnection() async {
        let confirmed = TailscaleFixtures.snapshot()
        var initial = TailscaleFeature.State()
        initial.snapshot = confirmed
        let store = TestStore(initialState: initial) { TailscaleFeature() } withDependencies: {
            $0.tailscaleClient.snapshot = { throw TailscaleError.unavailable }
        }
        store.exhaustivity = .off
        await store.send(.refresh)
        await store.receive(\.snapshotResponse)
        #expect(store.state.snapshot == confirmed)
        #expect(store.state.error == .unavailable)
        #expect(store.state.isLoading == false)
    }

    @Test func refreshRepairsASelectionThatWasRemovedExternally() async {
        let fresh = TailscaleFixtures.snapshot(accounts: [TailscaleFixtures.account("work")])
        var initial = TailscaleFeature.State()
        initial.selectedAccountID = "removed"
        let store = TestStore(initialState: initial) { TailscaleFeature() } withDependencies: {
            $0.tailscaleClient.snapshot = { fresh }
        }
        store.exhaustivity = .off
        await store.send(.refresh)
        await store.receive(\.snapshotResponse)
        #expect(store.state.selectedAccountID == "work")
    }

    @Test func selectionDoesNotSilentlySwitchTheVPNAccount() async {
        let recorder = TailscaleOperationRecorder()
        var initial = TailscaleFeature.State()
        initial.snapshot = TailscaleFixtures.snapshot(accounts: [TailscaleFixtures.account(), TailscaleFixtures.account("work", active: false)])
        let store = TestStore(initialState: initial) { TailscaleFeature() } withDependencies: {
            $0.tailscaleClient.perform = { await recorder.record($0) }
        }
        store.exhaustivity = .off
        await store.send(.selectAccount("work"))
        #expect(store.state.selectedAccountID == "work")
        #expect(await recorder.operations.isEmpty)
    }

    @Test func failedConnectionDoesNotOptimisticallyChangeTheSwitch() async {
        let recorder = TailscaleOperationRecorder()
        let confirmed = TailscaleFixtures.snapshot(status: .stopped)
        var initial = TailscaleFeature.State()
        initial.snapshot = confirmed
        let store = TestStore(initialState: initial) { TailscaleFeature() } withDependencies: {
            $0.tailscaleClient.perform = {
                await recorder.record($0)
                throw TailscaleError.authenticationRequired
            }
            $0.tailscaleClient.snapshot = { confirmed }
        }
        store.exhaustivity = .off
        await store.send(.connectChanged(true))
        await store.receive(\.operationFailed)
        await store.finish()
        #expect(await recorder.operations == [.forAccount("home", .connect)])
        #expect(store.state.snapshot?.connection.status == .stopped)
        #expect(store.state.error == .authenticationRequired)
        #expect(store.state.mutation == nil)
    }

    @Test func overlappingUserMutationsAreIgnored() async {
        let recorder = TailscaleOperationRecorder()
        var initial = TailscaleFeature.State()
        initial.snapshot = TailscaleFixtures.snapshot()
        initial.mutation = .login
        let store = TestStore(initialState: initial) { TailscaleFeature() } withDependencies: {
            $0.tailscaleClient.perform = { await recorder.record($0) }
        }
        store.exhaustivity = .off
        await store.send(.connectChanged(false))
        await store.send(.preferenceChanged(.acceptDNS, false))
        #expect(store.state.mutation == .login)
        #expect(await recorder.operations.isEmpty)
    }

    @Test func oldRefreshCannotOverwriteANewerAccountSnapshot() async {
        let confirmed = TailscaleFixtures.snapshot(accounts: [TailscaleFixtures.account("work")])
        var initial = TailscaleFeature.State()
        initial.snapshot = confirmed
        initial.generation = 2
        let store = TestStore(initialState: initial) { TailscaleFeature() }
        await store.send(.snapshotResponse(1, .success(TailscaleFixtures.snapshot())))
        #expect(store.state.snapshot == confirmed)
    }

    @Test func unavailablePreferenceCannotBeChangedAsIfItWereFalse() async {
        let recorder = TailscaleOperationRecorder()
        var initial = TailscaleFeature.State()
        initial.snapshot = TailscaleFixtures.snapshot()
        let store = TestStore(initialState: initial) { TailscaleFeature() } withDependencies: {
            $0.tailscaleClient.perform = { await recorder.record($0) }
        }
        store.exhaustivity = .off
        await store.send(.preferenceChanged(.advertiseExitNode, true))
        #expect(await recorder.operations.isEmpty)
        #expect(store.state.snapshot?.preferences[.advertiseExitNode] == nil)
    }
}

private actor TailscaleFeatureGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var open = false
    func wait() async {
        guard !open else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { open = true; continuation?.resume(); continuation = nil }
}
#endif
