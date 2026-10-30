import ComposableArchitecture
import Foundation
import Testing
@testable import DisplayBrightness

@MainActor
struct DisplayBrightnessFeatureTests {
    @Test func editsOnlyTheSelectedDisplayAndConfirmsAppliedValue() async {
        let writes = LockIsolated<[BrightnessRequest]>([])
        let store = TestStore(initialState: populatedState()) { DisplayBrightnessFeature() } withDependencies: {
            $0.displayBrightnessClient.apply = { request in writes.withValue { $0.append(request) } }
        }
        await store.send(.levelChanged(screenID: 1, level: 0.4)) {
            $0.snapshot.displays[0].level = 0.4
            $0.revisions[1] = 1
            $0.pending[1] = 1
        }
        await store.receive(\.applyCompleted) {
            $0.snapshot.displays[0].appliedLevel = 0.4
            $0.pending[1] = nil
        }
        #expect(writes.value == [.init(screenID: 1, generation: 3, level: 0.4, revision: 1)])
        #expect(store.state.snapshot.displays[1].level == 0.8)
        await store.finish()
    }

    @Test func unavailableAndNonfiniteRequestsNeverReachHardware() async {
        var initial = populatedState()
        initial.snapshot.displays[0].control = .unavailable
        let store = TestStore(initialState: initial) { DisplayBrightnessFeature() }
        await store.send(.levelChanged(screenID: 1, level: 0.2))
        await store.send(.levelChanged(screenID: 2, level: .nan))
        await store.send(.levelChanged(screenID: 99, level: 0.2))
    }

    @Test func failedWriteKeepsLastAppliedValueAndShowsFailure() async {
        let store = TestStore(initialState: populatedState()) { DisplayBrightnessFeature() } withDependencies: {
            $0.displayBrightnessClient.apply = { _ in throw BrightnessError.writeFailed }
        }
        await store.send(.levelChanged(screenID: 1, level: 0.1)) {
            $0.snapshot.displays[0].level = 0.1
            $0.revisions[1] = 1
            $0.pending[1] = 1
        }
        await store.receive(\.applyFailed) {
            $0.snapshot.displays[0].error = true
            $0.pending[1] = nil
        }
        #expect(store.state.snapshot.displays[0].appliedLevel == 0.8)
    }

    @Test func staleResponsesCannotChangeANewerRequestOrTopology() async {
        var initial = populatedState()
        initial.revisions[1] = 5
        initial.pending[1] = 5
        let store = TestStore(initialState: initial) { DisplayBrightnessFeature() }
        await store.send(.applyCompleted(screenID: 1, generation: 3, revision: 4, level: 0.2))
        await store.send(.applyFailed(screenID: 1, generation: 2, revision: 5))
        await store.send(.snapshotReceived(.init(generation: 2, displays: [])))
        #expect(store.state.snapshot.displays.count == 2)
        #expect(store.state.pending[1] == 5)
    }

    @Test func snapshotPreservesDraggedTargetWhileAcceptingAppliedProgress() async {
        var initial = populatedState()
        initial.snapshot.displays[0].level = 0.2
        initial.revisions[1] = 2
        initial.pending[1] = 2
        let store = TestStore(initialState: initial) { DisplayBrightnessFeature() }
        var progress = initial.snapshot
        progress.displays[0].level = 0.6
        progress.displays[0].appliedLevel = 0.6
        await store.send(.snapshotReceived(progress)) {
            $0.snapshot.displays[0].appliedLevel = 0.6
        }
        await store.send(.snapshotReceived(.init(generation: 4, displays: []))) {
            $0.snapshot = .init(generation: 4, displays: [])
            $0.pending = [:]
            $0.revisions = [:]
        }
    }

    @Test func aFailedSettingsSaveRestoresPersistedSettings() async {
        let store = TestStore(initialState: DisplayBrightnessFeature.State()) { DisplayBrightnessFeature() } withDependencies: {
            $0.displayBrightnessClient.saveSettings = { _ in throw BrightnessError.writeFailed }
        }
        var changed = BrightnessSettings()
        changed.allowZeroSoftwareBrightness = true
        await store.send(.settingsChanged(changed)) {
            $0.settings = changed
            $0.settingsRevision = 1
            $0.isSavingSettings = true
        }
        await store.receive(\.settingsSaveFailed) {
            $0.settings = BrightnessSettings()
            $0.isSavingSettings = false
            $0.settingsSaveFailed = true
        }
    }

    @Test func hostsShareOneObservationAndLastDisappearanceCancelsIt() async {
        let stream = AsyncStream<BrightnessSnapshot>.makeStream()
        let subscriptions = LockIsolated(0)
        let first = UUID(), second = UUID()
        let store = TestStore(initialState: DisplayBrightnessFeature.State()) { DisplayBrightnessFeature() } withDependencies: {
            $0.displayBrightnessClient.events = {
                subscriptions.withValue { $0 += 1 }
                return stream.stream
            }
        }
        await store.send(.appeared(hostID: first)) {
            $0.hosts = [first]
            $0.isRefreshing = true
            $0.refreshID = 1
        }
        await store.receive(\.settingsLoaded)
        await store.receive(\.scanCompleted) { $0.isRefreshing = false }
        await store.send(.appeared(hostID: second)) { $0.hosts.insert(second) }
        await store.send(.disappeared(hostID: first)) { $0.hosts.remove(first) }
        #expect(subscriptions.value == 1)
        await store.send(.disappeared(hostID: second)) { $0.hosts.remove(second) }
        await store.finish()
        stream.continuation.finish()
    }

    @Test func rapidSettingsEditsAreSavedInOrderWithoutRevertingTheLatestChoice() async {
        let clock = TestClock()
        let saves = LockIsolated<[BrightnessSettings]>([])
        let store = TestStore(initialState: DisplayBrightnessFeature.State()) { DisplayBrightnessFeature() } withDependencies: {
            $0.displayBrightnessClient.saveSettings = { value in
                saves.withValue { $0.append(value) }
                try await clock.sleep(for: .seconds(1))
            }
        }
        var first = BrightnessSettings()
        first.allowZeroSoftwareBrightness = true
        var latest = first
        latest.combinedDimming = false
        await store.send(.settingsChanged(first)) {
            $0.settings = first
            $0.settingsRevision = 1
            $0.isSavingSettings = true
        }
        await store.send(.settingsChanged(latest)) {
            $0.settings = latest
            $0.settingsRevision = 2
        }
        await clock.advance(by: .seconds(1))
        await store.receive(\.settingsSaved) { $0.persistedSettings = first }
        #expect(store.state.settings == latest)
        await clock.advance(by: .seconds(1))
        await store.receive(\.settingsSaved) {
            $0.persistedSettings = latest
            $0.isSavingSettings = false
        }
        #expect(saves.value == [first, latest])
        await store.finish()
    }

    @Test func aStaleRefreshCannotReplaceCurrentInventory() async {
        var initial = populatedState()
        initial.refreshID = 4
        initial.isRefreshing = true
        let store = TestStore(initialState: initial) { DisplayBrightnessFeature() }
        await store.send(.scanCompleted(requestID: 3, snapshot: .init(generation: 4, displays: [])))
        #expect(store.state.snapshot.displays.count == 2)
        #expect(store.state.isRefreshing)
    }

    @Test func requestingKeyboardAccessUsesInjectedPermissionEffect() async {
        let requests = LockIsolated(0)
        let store = TestStore(initialState: populatedState()) { DisplayBrightnessFeature() } withDependencies: {
            $0.displayBrightnessClient.requestKeyboardAccess = { requests.withValue { $0 += 1 } }
        }
        await store.send(.requestKeyboardAccess)
        await store.finish()
        #expect(requests.value == 1)
    }

    @Test func keyboardPermissionStatusDoesNotDisableSliders() async {
        var snapshot = populatedState().snapshot
        snapshot.brightnessKeyStatus = .needsAccessibility
        let store = TestStore(initialState: populatedState()) { DisplayBrightnessFeature() }
        await store.send(.snapshotReceived(snapshot)) { $0.snapshot.brightnessKeyStatus = .needsAccessibility }
        await store.send(.levelChanged(screenID: 2, level: 0.6)) {
            $0.snapshot.displays[1].level = 0.6
            $0.revisions[2] = 1
            $0.pending[2] = 1
        }
        await store.receive(\.applyCompleted) {
            $0.snapshot.displays[1].appliedLevel = 0.6
            $0.pending[2] = nil
        }
    }

    @Test func keyboardIntentSupersedesAndCancelsAnAcceptedPendingSliderWithoutFalseFailure() async {
        let clock = TestClock()
        let store = TestStore(initialState: populatedState()) { DisplayBrightnessFeature() } withDependencies: {
            $0.displayBrightnessClient.apply = { _ in try await clock.sleep(for: .seconds(10)) }
        }
        await store.send(.levelChanged(screenID: 2, level: 0.2)) {
            $0.snapshot.displays[1].level = 0.2
            $0.revisions[2] = 1
            $0.pending[2] = 1
        }
        var keyboard = store.state.snapshot
        keyboard.displays[1].level = 0.3
        keyboard.displays[1].appliedLevel = 0.3
        keyboard.displays[1].supersededUIRevision = 1
        await store.send(.snapshotReceived(keyboard)) {
            $0.snapshot = keyboard
            $0.pending[2] = nil
        }
        await store.send(.applyFailed(screenID: 2, generation: 3, revision: 1))
        await store.send(.applyCompleted(screenID: 2, generation: 3, revision: 1, level: 0.2))
        #expect(store.state.snapshot.displays[1].error == false)
        #expect(store.state.snapshot.displays[1].level == 0.3)
        #expect(store.state.revisions[2] == 1)
        // No clock advance: finish proves supersession cancelled the suspended slider effect.
        await store.finish()
    }

    @Test func anOldKeyboardSnapshotCannotSupersedeANewerSliderRevision() async {
        var initial = populatedState()
        initial.snapshot.displays[1].level = 0.6
        initial.pending[2] = 2
        initial.revisions[2] = 2
        let store = TestStore(initialState: initial) { DisplayBrightnessFeature() }
        var olderKeyboard = initial.snapshot
        olderKeyboard.displays[1].level = 0.3
        olderKeyboard.displays[1].appliedLevel = 0.3
        olderKeyboard.displays[1].supersededUIRevision = 1
        await store.send(.snapshotReceived(olderKeyboard)) {
            $0.snapshot.displays[1].appliedLevel = 0.3
            $0.snapshot.displays[1].supersededUIRevision = 1
        }
        await store.send(.applyFailed(screenID: 2, generation: 3, revision: 1))
        #expect(store.state.pending[2] == 2)
        #expect(store.state.snapshot.displays[1].level == 0.6)
        #expect(store.state.snapshot.displays[1].error == false)
    }

    private func populatedState() -> DisplayBrightnessFeature.State {
        var state = DisplayBrightnessFeature.State()
        state.snapshot = .init(generation: 3, displays: [
            .init(id: 1, name: "Built-in", control: .native, level: 0.8),
            .init(id: 2, name: "External", control: .ddc, level: 0.8)
        ])
        return state
    }
}
