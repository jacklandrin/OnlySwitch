import ComposableArchitecture
import Foundation
import RemoteCore
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteSoundMixerFeatureTests {
    private let macID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    private let otherMacID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!

    @Test func visibleEntitledAuthenticatedStartsStreaming() async {
        let spy = SoundMixerConnectionSpy()
        let store = makeStore(initialState: idleState(isEntitled: true), spy: spy)

        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
            $0.isStreamRequested = true
        }
        await store.receive(.streamingResponse(.success(true))) { $0.isStreaming = true }
        #expect(await spy.streaming == [true])
    }

    @Test func notEntitledNeverStreams() async {
        let spy = SoundMixerConnectionSpy()
        let store = makeStore(initialState: idleState(isEntitled: false), spy: spy)

        await store.send(.visibilityChanged(true)) { $0.isVisible = true }
        await store.finish()
        #expect(await spy.streaming.isEmpty)

        await store.send(.entitlementChanged(true)) {
            $0.isEntitled = true
            $0.isStreamRequested = true
        }
        await store.receive(.streamingResponse(.success(true))) { $0.isStreaming = true }
        #expect(await spy.streaming == [true])
    }

    @Test func losingEntitlementOrVisibilityStops() async {
        let spy = SoundMixerConnectionSpy()
        let store = makeStore(initialState: idleState(isEntitled: true), spy: spy)

        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
            $0.isStreamRequested = true
        }
        await store.receive(.streamingResponse(.success(true))) { $0.isStreaming = true }
        await store.send(.entitlementChanged(false)) {
            $0.isEntitled = false
            $0.isStreamRequested = false
            $0.isStreaming = false
        }
        await store.finish()
        #expect(await spy.streaming == [true, false])

        await store.send(.entitlementChanged(true)) {
            $0.isEntitled = true
            $0.isStreamRequested = true
        }
        await store.receive(.streamingResponse(.success(true))) { $0.isStreaming = true }
        await store.send(.visibilityChanged(false)) {
            $0.isVisible = false
            $0.isStreamRequested = false
            $0.isStreaming = false
        }
        await store.finish()
        #expect(await spy.streaming == [true, false, true, false])
    }

    @Test func upgradeRequiredShowsMessage() async {
        let store = TestStore(initialState: idleState(isEntitled: true)) { RemoteSoundMixerFeature() } withDependencies: {
            $0.remoteConnection.setSoundMixerStreaming = { _ in
                throw RemoteProtocolError(code: .upgradeRequired, message: "")
            }
        }

        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
            $0.isStreamRequested = true
        }
        await store.receive(.streamingResponse(.failure(.init(code: .upgradeRequired, message: "")))) {
            $0.availabilityMessage = "This Mac needs a newer OnlySwitch version to use Sound Mixer."
        }
    }

    @Test func snapshotEventsForOtherMacsIgnoredAndStaleRevisionsDropped() async {
        var state = streamingState()
        state.snapshot = nil
        let store = TestStore(initialState: state) { RemoteSoundMixerFeature() }
        let current = makeSnapshot(revision: 5)

        await store.send(.connectionEvent(.soundMixer(otherMacID, current)))
        await store.send(.connectionEvent(.soundMixer(macID, current))) { $0.snapshot = current }
        await store.send(.connectionEvent(.soundMixer(macID, makeSnapshot(revision: 3, isEnabled: false))))
        let sameRevision = makeSnapshot(revision: 5, isEnabled: false)
        await store.send(.connectionEvent(.soundMixer(macID, sameRevision))) { $0.snapshot = sameRevision }
    }

    @Test func sliderDebouncesToLatestValue() async {
        let spy = SoundMixerConnectionSpy()
        let clock = TestClock()
        let store = makeStore(initialState: streamingState(), spy: spy, clock: clock)

        await store.send(.volumeChanged(target: "a", value: 10)) {
            $0.draftVolumes["a"] = 10
            $0.activeDrags = ["a"]
        }
        await clock.advance(by: .milliseconds(10))
        await store.send(.volumeChanged(target: "a", value: 20)) { $0.draftVolumes["a"] = 20 }
        await clock.advance(by: .milliseconds(10))
        await store.send(.volumeChanged(target: "a", value: 30)) { $0.draftVolumes["a"] = 30 }
        await clock.advance(by: .milliseconds(30))
        #expect(await spy.commands.isEmpty)
        await clock.advance(by: .milliseconds(30))
        await store.receive(.commandFinished(nil))
        #expect(await spy.commands == [.setAppVolume(id: "a", volume: 30)])
        #expect(store.state.draftVolumes["a"] == 30)

        await store.send(.volumeCommitted(target: "a")) { $0.activeDrags = [] }
        await store.receive(.commandFinished(nil))
        #expect(await spy.commands == [.setAppVolume(id: "a", volume: 30), .setAppVolume(id: "a", volume: 30)])

        let next = makeSnapshot(revision: 2)
        await store.send(.connectionEvent(.soundMixer(macID, next))) {
            $0.snapshot = next
            $0.draftVolumes = [:]
        }
    }

    @Test func systemTargetSendsSetSystemVolume() async {
        let spy = SoundMixerConnectionSpy()
        let clock = TestClock()
        let store = makeStore(initialState: streamingState(), spy: spy, clock: clock)
        let systemKey = RemoteSoundMixerFeature.systemKey

        await store.send(.volumeChanged(target: systemKey, value: 140)) {
            $0.draftVolumes[systemKey] = 100
            $0.activeDrags = [systemKey]
        }
        await clock.advance(by: RemoteSoundMixerFeature.debounce)
        await store.receive(.commandFinished(nil))
        await store.send(.muteToggled(appID: "b"))
        await store.receive(.commandFinished(nil))

        #expect(await spy.commands == [.setSystemVolume(100), .setAppMuted(id: "b", isMuted: false)])
    }

    @Test func equalizerAndRoutingCommands() async {
        let spy = SoundMixerConnectionSpy()
        let clock = TestClock()
        let store = makeStore(initialState: streamingState(), spy: spy, clock: clock)

        await store.send(.gainChanged(appID: "a", band: 2, gain: 3)) {
            $0.draftGains["a"] = [2: 3]
            $0.activeDrags = ["a#eq2"]
        }
        await clock.advance(by: RemoteSoundMixerFeature.debounce)
        await store.receive(.commandFinished(nil))
        await store.send(.gainChanged(appID: "a", band: 10, gain: 3))
        await store.send(.equalizerReset(appID: "a")) {
            $0.draftGains = [:]
            $0.activeDrags = []
        }
        await store.receive(.commandFinished(nil))
        await store.send(.outputDeviceToggled(appID: "a", deviceID: "dev2"))
        await store.receive(.commandFinished(nil))
        await store.send(.outputDeviceToggled(appID: "a", deviceID: "unknown"))
        await store.send(.followSystemOutput(appID: "a"))
        await store.receive(.commandFinished(nil))

        #expect(await spy.commands == [
            .setAppEqualizerGain(id: "a", band: 2, gain: 3),
            .resetAppEqualizer(id: "a"),
            .toggleAppOutputDevice(id: "a", deviceID: "dev2"),
            .followSystemOutput(id: "a"),
        ])
    }

    @Test(arguments: [false, true])
    func commandsIgnoredWhenMixerDisabledOrNotStreaming(isStreaming: Bool) async {
        let spy = SoundMixerConnectionSpy()
        var state = streamingState()
        state.isStreaming = isStreaming
        if isStreaming { state.snapshot = makeSnapshot(isEnabled: false) }
        let store = makeStore(initialState: state, spy: spy)

        await store.send(.volumeChanged(target: "a", value: 10))
        await store.send(.volumeChanged(target: RemoteSoundMixerFeature.systemKey, value: 10))
        await store.send(.muteToggled(appID: "a"))
        await store.send(.gainChanged(appID: "a", band: 1, gain: 2))
        await store.send(.equalizerReset(appID: "a"))
        await store.send(.outputDeviceToggled(appID: "a", deviceID: "dev2"))
        await store.send(.followSystemOutput(appID: "a"))
        await store.finish()

        #expect(await spy.commands.isEmpty)
    }

    @Test func appRemovedFromSnapshotDropsExpansionAndDrafts() async {
        let systemKey = RemoteSoundMixerFeature.systemKey
        var state = streamingState()
        state.expandedAppIDs = ["a", "b"]
        state.draftVolumes = ["a": 10, "b": 20, systemKey: 30]
        state.activeDrags = ["a", "b", systemKey, "b#eq1"]
        state.draftGains = ["b": [1: 2]]
        let store = TestStore(initialState: state) { RemoteSoundMixerFeature() }
        let next = makeSnapshot(revision: 2, apps: [makeApps()[0]])

        await store.send(.connectionEvent(.soundMixer(macID, next))) {
            $0.snapshot = next
            $0.expandedAppIDs = ["a"]
            $0.draftVolumes = ["a": 10, systemKey: 30]
            $0.activeDrags = ["a", systemKey]
            $0.draftGains = [:]
        }
    }

    @Test func offlineResetsTransientState() async {
        var state = streamingState()
        state.expandedAppIDs = ["a"]
        state.draftVolumes = ["a": 10]
        state.draftGains = ["a": [1: 2]]
        state.activeDrags = ["a"]
        state.commandError = "Failed"
        let store = TestStore(initialState: state) { RemoteSoundMixerFeature() }

        await store.send(.connectionEvent(.offline(otherMacID, nil)))
        await store.send(.connectionEvent(.offline(macID, nil))) {
            $0.connectionState = .offline(nil)
            $0.isStreamRequested = false
            $0.isStreaming = false
            $0.snapshot = nil
            $0.expandedAppIDs = []
            $0.draftVolumes = [:]
            $0.draftGains = [:]
            $0.activeDrags = []
            $0.commandError = nil
        }
    }

    @Test func expansionToggles() async {
        let store = TestStore(initialState: streamingState()) { RemoteSoundMixerFeature() }

        await store.send(.expandedToggled(appID: "a")) { $0.expandedAppIDs = ["a"] }
        await store.send(.expandedToggled(appID: "a")) { $0.expandedAppIDs = [] }
    }

    @Test func commandFailureIsSurfacedAndClearedBySuccess() async {
        let store = TestStore(initialState: streamingState()) { RemoteSoundMixerFeature() }

        await store.send(.commandFinished(.init(code: .executionFailed, message: "Failed"))) {
            $0.commandError = "Failed"
        }
        await store.send(.commandFinished(nil)) { $0.commandError = nil }
    }

    private func makeStore(
        initialState: RemoteSoundMixerFeature.State,
        spy: SoundMixerConnectionSpy,
        clock: TestClock<Duration> = TestClock()
    ) -> TestStoreOf<RemoteSoundMixerFeature> {
        TestStore(initialState: initialState) { RemoteSoundMixerFeature() } withDependencies: {
            $0.continuousClock = clock
            $0.remoteConnection.setSoundMixerStreaming = { await spy.recordStreaming($0) }
            $0.remoteConnection.sendSoundMixer = { await spy.recordCommand($0) }
        }
    }

    private func idleState(isEntitled: Bool) -> RemoteSoundMixerFeature.State {
        var state = RemoteSoundMixerFeature.State()
        state.selectedMacID = macID
        state.connectionState = .authenticated
        state.isEntitled = isEntitled
        return state
    }

    private func streamingState() -> RemoteSoundMixerFeature.State {
        var state = idleState(isEntitled: true)
        state.isVisible = true
        state.isStreamRequested = true
        state.isStreaming = true
        state.snapshot = makeSnapshot()
        return state
    }

    private func makeApps() -> [RemoteSoundMixerApp] {
        [
            .init(
                id: "a",
                name: "Music",
                volume: 50,
                isMuted: false,
                equalizer: .init(gains: [], status: .flat),
                routing: .init(selectedDeviceIDs: [], status: .followingSystem)
            ),
            .init(id: "b", name: "Safari", volume: 70, isMuted: true),
        ]
    }

    private func makeSnapshot(
        revision: UInt64 = 1,
        isEnabled: Bool = true,
        apps: [RemoteSoundMixerApp]? = nil
    ) -> RemoteSoundMixerSnapshot {
        .init(
            revision: revision,
            isEnabled: isEnabled,
            systemVolume: 40,
            output: .init(name: "MacBook Pro Speakers", symbolName: "laptopcomputer"),
            apps: apps ?? makeApps(),
            outputDevices: [
                .init(id: "dev1", name: "MacBook Pro Speakers", isDefault: true),
                .init(id: "dev2", name: "AirPods Pro", isDefault: false),
            ]
        )
    }
}

private actor SoundMixerConnectionSpy {
    private(set) var streaming: [Bool] = []
    private(set) var commands: [RemoteSoundMixerCommand] = []

    func recordStreaming(_ enabled: Bool) { streaming.append(enabled) }
    func recordCommand(_ command: RemoteSoundMixerCommand) { commands.append(command) }
}
