import ComposableArchitecture
import Foundation
import RemoteCore
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteBrightnessFeatureTests {
    private let macID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
    private let otherMacID = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!

    @Test func visibleEntitledAuthenticatedStartsStreaming() async {
        let spy = BrightnessConnectionSpy()
        let store = makeStore(initialState: idleState(isEntitled: true), spy: spy)

        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
            $0.isStreamRequested = true
        }
        await store.receive(.streamingResponse(.success(true))) { $0.isStreaming = true }
        #expect(await spy.streaming == [true])
    }

    @Test func notEntitledNeverStreams() async {
        let spy = BrightnessConnectionSpy()
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
        let spy = BrightnessConnectionSpy()
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
        let store = TestStore(initialState: idleState(isEntitled: true)) { RemoteBrightnessFeature() } withDependencies: {
            $0.remoteConnection.setBrightnessStreaming = { _ in
                throw RemoteProtocolError(code: .upgradeRequired, message: "")
            }
        }

        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
            $0.isStreamRequested = true
        }
        await store.receive(.streamingResponse(.failure(.init(code: .upgradeRequired, message: "")))) {
            $0.availabilityMessage = "This Mac needs a newer OnlySwitch version to use Brightness."
        }
    }

    @Test func snapshotEventsForOtherMacsIgnoredAndStaleRevisionsDropped() async {
        var state = streamingState()
        state.snapshot = nil
        let store = TestStore(initialState: state) { RemoteBrightnessFeature() }
        let current = makeSnapshot(revision: 5)

        await store.send(.connectionEvent(.brightness(otherMacID, current)))
        await store.send(.connectionEvent(.brightness(macID, current))) { $0.snapshot = current }
        await store.send(.connectionEvent(.brightness(macID, makeSnapshot(revision: 3, level: 0.1))))
        let sameRevision = makeSnapshot(revision: 5, level: 0.2)
        await store.send(.connectionEvent(.brightness(macID, sameRevision))) { $0.snapshot = sameRevision }
    }

    @Test func snapshotsIgnoredUntilStreamIsRequested() async {
        var state = idleState(isEntitled: true)
        state.isVisible = false
        let store = TestStore(initialState: state) { RemoteBrightnessFeature() }

        await store.send(.connectionEvent(.brightness(macID, makeSnapshot())))
    }

    @Test func levelDebouncesAndClamps() async {
        let spy = BrightnessConnectionSpy()
        let clock = TestClock()
        let store = makeStore(initialState: streamingState(), spy: spy, clock: clock)

        await store.send(.levelChanged(displayID: 1, level: 0.9)) {
            $0.draftLevels[1] = 0.9
            $0.activeDrags = [1]
        }
        await clock.advance(by: .milliseconds(10))
        await store.send(.levelChanged(displayID: 1, level: 1.2)) { $0.draftLevels[1] = 1 }
        await clock.advance(by: .milliseconds(10))
        await store.send(.levelChanged(displayID: 1, level: 1.4))
        await clock.advance(by: .milliseconds(30))
        #expect(await spy.commands.isEmpty)
        await clock.advance(by: .milliseconds(30))
        await store.receive(.commandFinished(nil))
        #expect(await spy.commands == [.setLevel(displayID: 1, level: 1)])

        await store.send(.levelChanged(displayID: 1, level: -3)) { $0.draftLevels[1] = 0 }
        await store.send(.levelChanged(displayID: 1, level: .nan))
        await clock.advance(by: RemoteBrightnessFeature.debounce)
        await store.receive(.commandFinished(nil))
        #expect(await spy.commands == [.setLevel(displayID: 1, level: 1), .setLevel(displayID: 1, level: 0)])
    }

    @Test func commitSendsImmediately() async {
        let spy = BrightnessConnectionSpy()
        let clock = TestClock()
        let store = makeStore(initialState: streamingState(), spy: spy, clock: clock)

        await store.send(.levelChanged(displayID: 2, level: 0.25)) {
            $0.draftLevels[2] = 0.25
            $0.activeDrags = [2]
        }
        await store.send(.levelCommitted(displayID: 2)) { $0.activeDrags = [] }
        await store.receive(.commandFinished(nil))
        await clock.run()
        #expect(await spy.commands == [.setLevel(displayID: 2, level: 0.25)])
    }

    @Test func unavailableDisplayIgnoresChanges() async {
        let spy = BrightnessConnectionSpy()
        let clock = TestClock()
        let store = makeStore(initialState: streamingState(), spy: spy, clock: clock)

        await store.send(.levelChanged(displayID: 3, level: 0.5))
        await store.send(.levelCommitted(displayID: 3))
        await store.send(.levelChanged(displayID: 99, level: 0.5))
        await clock.run()
        await store.finish()
        #expect(await spy.commands.isEmpty)
    }

    @Test func snapshotDoesNotOverrideActiveDrag() async {
        let spy = BrightnessConnectionSpy()
        let clock = TestClock()
        let store = makeStore(initialState: streamingState(), spy: spy, clock: clock)

        await store.send(.levelChanged(displayID: 1, level: 0.3)) {
            $0.draftLevels[1] = 0.3
            $0.activeDrags = [1]
        }
        let during = makeSnapshot(revision: 2, level: 0.8)
        await store.send(.connectionEvent(.brightness(macID, during))) { $0.snapshot = during }
        #expect(store.state.level(for: 1) == 0.3)

        await store.send(.levelCommitted(displayID: 1)) { $0.activeDrags = [] }
        await store.receive(.commandFinished(nil))
        let after = makeSnapshot(revision: 3, level: 0.3)
        await store.send(.connectionEvent(.brightness(macID, after))) {
            $0.snapshot = after
            $0.draftLevels = [:]
        }
    }

    @Test func removedDisplayDropsDraftsAndDrags() async {
        var state = streamingState()
        state.draftLevels = [1: 0.2, 2: 0.4]
        state.activeDrags = [1, 2]
        let store = TestStore(initialState: state) { RemoteBrightnessFeature() }
        let next = RemoteBrightnessSnapshot(revision: 2, displays: [makeDisplays()[0]])

        await store.send(.connectionEvent(.brightness(macID, next))) {
            $0.snapshot = next
            $0.draftLevels = [1: 0.2]
            $0.activeDrags = [1]
        }
    }

    @Test func commandsIgnoredWhenNotStreaming() async {
        let spy = BrightnessConnectionSpy()
        let clock = TestClock()
        var state = streamingState()
        state.isStreaming = false
        let store = makeStore(initialState: state, spy: spy, clock: clock)

        await store.send(.levelChanged(displayID: 1, level: 0.5))
        await store.send(.levelCommitted(displayID: 1))
        await clock.run()
        await store.finish()
        #expect(await spy.commands.isEmpty)
    }

    @Test(arguments: [false, true])
    func offlineResetsTransientState(isRevoked: Bool) async {
        var state = streamingState()
        state.draftLevels = [1: 0.2]
        state.activeDrags = [1]
        state.commandError = "Failed"
        let store = TestStore(initialState: state) { RemoteBrightnessFeature() }

        let event: (UUID) -> RemoteConnectionEvent = { isRevoked ? .revoked($0) : .offline($0, nil) }
        await store.send(.connectionEvent(event(otherMacID)))
        await store.send(.connectionEvent(event(macID))) {
            $0.connectionState = isRevoked ? .revoked : .offline(nil)
            $0.isStreamRequested = false
            $0.isStreaming = false
            $0.snapshot = nil
            $0.draftLevels = [:]
            $0.activeDrags = []
            $0.commandError = nil
        }
    }

    @Test func reconnectingCancelsPendingCommandAndRestreamsWhenAuthenticated() async {
        let spy = BrightnessConnectionSpy()
        let clock = TestClock()
        let store = makeStore(initialState: streamingState(), spy: spy, clock: clock)

        await store.send(.levelChanged(displayID: 1, level: 0.4)) {
            $0.draftLevels[1] = 0.4
            $0.activeDrags = [1]
        }
        await store.send(.connectionEvent(.connecting(macID))) {
            $0.connectionState = .connecting
            $0.isStreamRequested = false
            $0.isStreaming = false
            $0.snapshot = nil
            $0.draftLevels = [:]
            $0.activeDrags = []
        }
        await clock.run()
        #expect(await spy.commands.isEmpty)

        await store.send(.connectionEvent(.authenticated(macID))) {
            $0.connectionState = .authenticated
            $0.isStreamRequested = true
        }
        await store.receive(.streamingResponse(.success(true))) { $0.isStreaming = true }
        #expect(await spy.streaming == [true])
    }

    @Test func commandFailureIsSurfacedAndClearedBySuccess() async {
        let store = TestStore(initialState: streamingState()) { RemoteBrightnessFeature() }

        await store.send(.commandFinished(.init(code: .executionFailed, message: "Failed"))) {
            $0.commandError = "Failed"
        }
        await store.send(.commandFinished(nil)) { $0.commandError = nil }
    }

    private func makeStore(
        initialState: RemoteBrightnessFeature.State,
        spy: BrightnessConnectionSpy,
        clock: TestClock<Duration> = TestClock()
    ) -> TestStoreOf<RemoteBrightnessFeature> {
        TestStore(initialState: initialState) { RemoteBrightnessFeature() } withDependencies: {
            $0.continuousClock = clock
            $0.remoteConnection.setBrightnessStreaming = { await spy.recordStreaming($0) }
            $0.remoteConnection.sendBrightness = { await spy.recordCommand($0) }
        }
    }

    private func idleState(isEntitled: Bool) -> RemoteBrightnessFeature.State {
        var state = RemoteBrightnessFeature.State()
        state.selectedMacID = macID
        state.connectionState = .authenticated
        state.isEntitled = isEntitled
        return state
    }

    private func streamingState() -> RemoteBrightnessFeature.State {
        var state = idleState(isEntitled: true)
        state.isVisible = true
        state.isStreamRequested = true
        state.isStreaming = true
        state.snapshot = makeSnapshot()
        return state
    }

    private func makeDisplays(level: Double = 0.7) -> [RemoteBrightnessDisplay] {
        [
            .init(id: 1, name: "Built-in Retina Display", control: .native, level: level, hasError: false),
            .init(id: 2, name: "Studio Display", control: .ddc, level: 0.5, hasError: false),
            .init(id: 3, name: "Projector", control: .unavailable, level: 1, hasError: false),
        ]
    }

    private func makeSnapshot(revision: UInt64 = 1, level: Double = 0.7) -> RemoteBrightnessSnapshot {
        .init(revision: revision, displays: makeDisplays(level: level))
    }
}

private actor BrightnessConnectionSpy {
    private(set) var streaming: [Bool] = []
    private(set) var commands: [RemoteBrightnessCommand] = []

    func recordStreaming(_ enabled: Bool) { streaming.append(enabled) }
    func recordCommand(_ command: RemoteBrightnessCommand) { commands.append(command) }
}
