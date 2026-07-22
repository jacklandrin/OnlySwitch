import ComposableArchitecture
import Foundation
import Testing
@testable import OnlySwitch

@MainActor
struct RemoteAccessSettingsFeatureTests {
    @Test
    func enablingPersistsPreferenceAndStartsHost() async {
        let recorder = RemoteAccessSettingsRecorder()
        let store = TestStore(initialState: RemoteAccessSettingsFeature.State(displayName: "Studio Mac")) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.remoteAccessPreferences = recorder.preferences
            $0.remoteHost = recorder.host
        }

        await store.send(.setEnabled(true)) {
            $0.isEnabled = true
            $0.hostStatus = .starting
        }
        await store.receive(.hostStarted)

        #expect(await recorder.enabledValues == [true])
        #expect(await recorder.startedNames == ["Studio Mac"])
    }

    @Test
    func pairingExpiresAfterSingleTickFollowingLargeDateJump() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let recorder = RemoteAccessSettingsRecorder(
            pairingWindow: PairingWindow(code: "ABCDEFGH2345", expiresAt: now.addingTimeInterval(2))
        )
        var state = RemoteAccessSettingsFeature.State(isEnabled: true, displayName: "Studio Mac")
        state.hostStatus = .listening(port: 42)
        let store = TestStore(initialState: state) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.date.now = now
            $0.remoteAccessPreferences = recorder.preferences
            $0.remoteHost = recorder.host
        }

        await store.send(.startPairingTapped) {
            $0.isPairingRequestInFlight = true
        }
        await store.receive(.pairingStarted(recorder.pairingWindow)) {
            $0.isPairingRequestInFlight = false
            $0.pairingCode = "ABCDEFGH2345"
            $0.pairingExpiresAt = now.addingTimeInterval(2)
            $0.pairingSecondsRemaining = 2
        }
        await store.send(.pairingTick(now.addingTimeInterval(60))) {
            $0.pairingCode = nil
            $0.pairingExpiresAt = nil
            $0.pairingSecondsRemaining = 0
        }
        await store.receive(.pairingCancelled)

        #expect(await recorder.cancelPairingCount == 1)
        #expect(await recorder.enabledValues.isEmpty)
        #expect(await recorder.displayNameValues.isEmpty)
    }

    @Test
    func hostEventsRefreshStatusConnectionCountAndCredentialFreeDevices() async {
        let deviceID = UUID()
        let lastConnectedAt = Date(timeIntervalSince1970: 500)
        let (events, continuation) = AsyncStream.makeStream(of: RemoteHostEvent.self)
        let recorder = RemoteAccessSettingsRecorder(events: events)
        let store = TestStore(initialState: RemoteAccessSettingsFeature.State(isEnabled: true)) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.remoteAccessPreferences = recorder.preferences
            $0.remoteHost = recorder.host
        }

        await store.send(.task)
        await store.receive(.devicesResponse(.success([])))
        continuation.yield(.statusChanged(.listening(port: 9_999)))
        await store.receive(.hostEvent(.statusChanged(.listening(port: 9_999)))) {
            $0.hostStatus = .listening(port: 9_999)
        }
        continuation.yield(.connectionCountChanged(2))
        await store.receive(.hostEvent(.connectionCountChanged(2))) {
            $0.connectionCount = 2
        }
        continuation.yield(.devicesChanged([
            PairedRemoteDevice(
                id: deviceID,
                name: "My iPad",
                credential: Data(repeating: 7, count: 32),
                createdAt: .distantPast,
                lastConnectedAt: lastConnectedAt
            )
        ]))
        await store.receive(.hostEvent(.devicesChanged([
            PairedRemoteDevice(
                id: deviceID,
                name: "My iPad",
                credential: Data(repeating: 7, count: 32),
                createdAt: .distantPast,
                lastConnectedAt: lastConnectedAt
            )
        ]))) {
            $0.pairedDevices = [
                .init(id: deviceID, name: "My iPad", lastConnectedAt: lastConnectedAt)
            ]
        }
        continuation.finish()
        await store.finish()
    }

    @Test
    func rapidDisplayNameChangesPersistAndRestartOnlyLatestName() async {
        let clock = TestClock()
        let recorder = RemoteAccessSettingsRecorder()
        var state = RemoteAccessSettingsFeature.State(isEnabled: true, displayName: "Old Mac")
        state.hostStatus = .listening(port: 42)
        let store = TestStore(initialState: state) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.remoteAccessPreferences = recorder.preferences
            $0.remoteHost = recorder.host
        }

        await store.send(.displayNameChanged("Studio")) {
            $0.displayName = "Studio"
        }
        await store.send(.displayNameChanged("Studio Mac")) {
            $0.displayName = "Studio Mac"
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(.commitDisplayName) {
            $0.hostStatus = .starting
        }
        await store.receive(.hostStarted)

        #expect(await recorder.displayNameValues == ["Studio Mac"])
        #expect(await recorder.startedNames == ["Studio Mac"])
    }

    @Test
    func disabledDisplayNameIsNormalizedAndPersistedWithoutStartingHost() async {
        let clock = TestClock()
        let recorder = RemoteAccessSettingsRecorder()
        let store = TestStore(initialState: RemoteAccessSettingsFeature.State(isEnabled: false)) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.remoteAccessPreferences = recorder.preferences
            $0.remoteHost = recorder.host
        }

        await store.send(.displayNameChanged("  Desk Mac  ")) {
            $0.displayName = "  Desk Mac  "
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(.commitDisplayName)

        #expect(await recorder.displayNameValues == ["Desk Mac"])
        #expect(await recorder.startedNames.isEmpty)
    }

    @Test
    func displayNameEditSurvivesDisablingBeforeDebounceCompletes() async {
        let clock = TestClock()
        let recorder = RemoteAccessSettingsRecorder()
        let store = TestStore(
            initialState: RemoteAccessSettingsFeature.State(isEnabled: true, displayName: "Old Mac")
        ) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.remoteAccessPreferences = recorder.preferences
            $0.remoteHost = recorder.host
        }

        await store.send(.displayNameChanged("  New Mac  ")) {
            $0.displayName = "  New Mac  "
        }
        await store.send(.setEnabled(false)) {
            $0.isEnabled = false
        }
        await store.receive(.hostStopped)
        await clock.advance(by: .milliseconds(350))
        await store.receive(.commitDisplayName)

        #expect(await recorder.displayNameValues == ["New Mac"])
        #expect(await recorder.startedNames.isEmpty)
    }

    @Test
    func disablingCancelsInFlightPairingWithoutPublishingAnError() async {
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let (gate, gateContinuation) = AsyncStream.makeStream(of: Void.self)
        let recorder = RemoteAccessSettingsRecorder()
        let host = RemoteHostClient(
            start: { _ in },
            stop: {},
            startPairing: {
                startedContinuation.yield(())
                for await _ in gate { break }
                try Task.checkCancellation()
                return recorder.pairingWindow
            },
            cancelPairing: {},
            revoke: { _ in },
            pairedDevices: { [] },
            events: { .finished }
        )
        let store = TestStore(initialState: RemoteAccessSettingsFeature.State(isEnabled: true)) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.remoteAccessPreferences = recorder.preferences
            $0.remoteHost = host
        }

        await store.send(.startPairingTapped) {
            $0.isPairingRequestInFlight = true
        }
        var startedIterator = started.makeAsyncIterator()
        _ = await startedIterator.next()
        startedContinuation.finish()
        await store.send(.setEnabled(false)) {
            $0.isEnabled = false
            $0.isPairingRequestInFlight = false
        }
        gateContinuation.finish()
        await store.receive(.hostStopped)
        await store.finish()
    }

    @Test
    func hostStartFailurePublishesSafeErrorState() async {
        let recorder = RemoteAccessSettingsRecorder(startError: .operationFailed)
        let store = TestStore(initialState: RemoteAccessSettingsFeature.State()) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.remoteAccessPreferences = recorder.preferences
            $0.remoteHost = recorder.host
        }

        await store.send(.setEnabled(true)) {
            $0.isEnabled = true
            $0.hostStatus = .starting
        }
        await store.receive(.hostFailed("Test operation failed")) {
            $0.hostStatus = .failed("Test operation failed")
            $0.alert = .error("Test operation failed")
        }
    }

    @Test
    func terminalStopBeforeDelayedConfigurationPreventsHostStart() async {
        let recorder = RemoteControllerHostRecorder()
        let (configurationStarted, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let (configurationGate, gateContinuation) = AsyncStream.makeStream(of: Void.self)
        let controller = RemoteAccessController(
            remoteHost: recorder.host,
            configuration: {
                startedContinuation.yield(())
                for await _ in configurationGate { break }
                return .init(isEnabled: true, displayName: "Studio Mac")
            }
        )

        let startup = Task { await controller.startIfEnabled() }
        var startedIterator = configurationStarted.makeAsyncIterator()
        _ = await startedIterator.next()
        startedContinuation.finish()
        await controller.stopForTermination()
        gateContinuation.yield(())
        gateContinuation.finish()
        await startup.value

        #expect(await recorder.startCount == 0)
        #expect(await recorder.stopCount == 1)
    }

    @Test
    func terminalStopCleansUpStartThatWasAlreadySuspended() async {
        let recorder = RemoteControllerHostRecorder()
        let (hostStarted, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let (hostGate, gateContinuation) = AsyncStream.makeStream(of: Void.self)
        let host = RemoteHostClient(
            start: { configuration in
                await recorder.recordStart(configuration)
                startedContinuation.yield(())
                for await _ in hostGate { break }
            },
            stop: {
                await recorder.recordStop()
                gateContinuation.yield(())
            },
            startPairing: { .init(code: "ABCDEFGH2345", expiresAt: .distantFuture) },
            cancelPairing: {},
            revoke: { _ in },
            pairedDevices: { [] },
            events: { .finished }
        )
        let controller = RemoteAccessController(
            remoteHost: host,
            configuration: { .init(isEnabled: true, displayName: "Studio Mac") }
        )

        let startup = Task { await controller.startIfEnabled() }
        var startedIterator = hostStarted.makeAsyncIterator()
        _ = await startedIterator.next()
        startedContinuation.finish()
        await controller.stopForTermination()
        gateContinuation.finish()
        await startup.value

        #expect(await recorder.startCount == 1)
        #expect(await recorder.stopCount == 2)
    }

    @Test
    func ordinaryStopLeavesControllerRestartable() async {
        let recorder = RemoteControllerHostRecorder()
        let controller = RemoteAccessController(
            remoteHost: recorder.host,
            configuration: { .init(isEnabled: true, displayName: "Studio Mac") }
        )

        await controller.startIfEnabled()
        await controller.stop()
        await controller.startIfEnabled()

        #expect(await recorder.startCount == 2)
        #expect(await recorder.stopCount == 1)
    }

    @Test
    func confirmedRevocationRemovesDevice() async {
        let deviceID = UUID()
        let recorder = RemoteAccessSettingsRecorder()
        var state = RemoteAccessSettingsFeature.State()
        state.pairedDevices = [.init(id: deviceID, name: "My iPhone", lastConnectedAt: nil)]
        let store = TestStore(initialState: state) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.remoteAccessPreferences = recorder.preferences
            $0.remoteHost = recorder.host
        }

        await store.send(.revokeTapped(deviceID)) {
            $0.alert = .revokeDevice(id: deviceID, name: "My iPhone")
        }
        await store.send(.alert(.presented(.confirmRevoke(deviceID)))) {
            $0.alert = nil
            $0.revokingDeviceIDs.insert(deviceID)
        }
        await store.receive(.revokeResponse(deviceID, .success([]))) {
            $0.revokingDeviceIDs.remove(deviceID)
            $0.pairedDevices = []
        }

        #expect(await recorder.revokedDeviceIDs == [deviceID])
    }

    @Test
    func copyingActivePairingCodeShowsTemporaryConfirmation() async {
        let clock = TestClock()
        let pasteboard = RemotePasteboardRecorder(result: true)
        var state = RemoteAccessSettingsFeature.State(isEnabled: true)
        state.pairingCode = "ABCDEFGH2345"
        let store = TestStore(initialState: state) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.remotePasteboard = pasteboard.client
        }

        await store.send(.copyPairingCodeTapped)
        await store.receive(.copyPairingCodeResponse(code: "ABCDEFGH2345", succeeded: true)) {
            $0.isPairingCodeCopied = true
        }
        #expect(await pasteboard.values == ["ABCDEFGH2345"])

        await clock.advance(by: .seconds(2))
        await store.receive(.clearPairingCodeCopied) {
            $0.isPairingCodeCopied = false
        }
    }

    @Test
    func copyingWithoutActivePairingDoesNothing() async {
        let pasteboard = RemotePasteboardRecorder(result: true)
        let store = TestStore(initialState: RemoteAccessSettingsFeature.State()) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.remotePasteboard = pasteboard.client
        }

        await store.send(.copyPairingCodeTapped)
        #expect(await pasteboard.values.isEmpty)
    }

    @Test
    func pasteboardFailureKeepsPairingAndShowsError() async {
        let pasteboard = RemotePasteboardRecorder(result: false)
        var state = RemoteAccessSettingsFeature.State(isEnabled: true)
        state.pairingCode = "ABCDEFGH2345"
        let store = TestStore(initialState: state) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.remotePasteboard = pasteboard.client
        }

        await store.send(.copyPairingCodeTapped)
        await store.receive(.copyPairingCodeResponse(code: "ABCDEFGH2345", succeeded: false)) {
            $0.alert = .error("The pairing code couldn’t be copied.")
        }
        #expect(store.state.pairingCode == "ABCDEFGH2345")
    }

    @Test
    func staleCopyResponseDoesNotShowFeedbackOrAnErrorForReplacementPairingCode() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let oldCode = "ABCDEFGH2345"
        let replacementWindow = PairingWindow(
            code: "JKLMNOPQ6789",
            expiresAt: now.addingTimeInterval(60)
        )
        let recorder = RemoteAccessSettingsRecorder()
        let clock = TestClock()
        let pasteboard = RemotePasteboardGate()
        var state = RemoteAccessSettingsFeature.State(isEnabled: true)
        state.pairingCode = oldCode
        let store = TestStore(initialState: state) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date.now = now
            $0.remotePasteboard = pasteboard.client
            $0.remoteHost = recorder.host
        }

        await store.send(.copyPairingCodeTapped)
        await pasteboard.waitForCopy()
        await store.send(.pairingStarted(replacementWindow)) {
            $0.pairingCode = replacementWindow.code
            $0.pairingExpiresAt = replacementWindow.expiresAt
            $0.pairingSecondsRemaining = 60
        }
        await pasteboard.respond(succeeded: true)
        await store.receive(.copyPairingCodeResponse(code: oldCode, succeeded: true))

        #expect(store.state.isPairingCodeCopied == false)
        #expect(store.state.alert == nil)

        await store.send(.cancelPairingTapped) {
            $0.pairingCode = nil
            $0.pairingExpiresAt = nil
            $0.pairingSecondsRemaining = 0
        }
        await store.receive(.pairingCancelled)
        #expect(await recorder.cancelPairingCount == 1)
    }

    @Test
    func changedCodePairingWindowRefreshClearsCopiedFeedback() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let replacementWindow = PairingWindow(
            code: "JKLMNOPQ6789",
            expiresAt: now.addingTimeInterval(60)
        )
        let recorder = RemoteAccessSettingsRecorder()
        let clock = TestClock()
        var state = RemoteAccessSettingsFeature.State(isEnabled: true)
        state.pairingCode = "ABCDEFGH2345"
        state.pairingExpiresAt = now.addingTimeInterval(30)
        state.pairingSecondsRemaining = 30
        state.isPairingCodeCopied = true
        let store = TestStore(initialState: state) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date.now = now
            $0.remoteHost = recorder.host
        }

        await store.send(.pairingStarted(replacementWindow)) {
            $0.pairingCode = replacementWindow.code
            $0.pairingExpiresAt = replacementWindow.expiresAt
            $0.pairingSecondsRemaining = 60
            $0.isPairingCodeCopied = false
        }

        await store.send(.cancelPairingTapped) {
            $0.pairingCode = nil
            $0.pairingExpiresAt = nil
            $0.pairingSecondsRemaining = 0
        }
        await store.receive(.pairingCancelled)
        #expect(await recorder.cancelPairingCount == 1)
    }

    @Test
    func sameCodePairingWindowRefreshPreservesCopiedFeedback() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let code = "ABCDEFGH2345"
        let refreshedWindow = PairingWindow(
            code: code,
            expiresAt: now.addingTimeInterval(60)
        )
        let recorder = RemoteAccessSettingsRecorder()
        let clock = TestClock()
        var state = RemoteAccessSettingsFeature.State(isEnabled: true)
        state.pairingCode = code
        state.pairingExpiresAt = now.addingTimeInterval(30)
        state.pairingSecondsRemaining = 30
        state.isPairingCodeCopied = true
        let store = TestStore(initialState: state) {
            RemoteAccessSettingsFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date.now = now
            $0.remoteHost = recorder.host
        }

        await store.send(.pairingStarted(refreshedWindow)) {
            $0.pairingExpiresAt = refreshedWindow.expiresAt
            $0.pairingSecondsRemaining = 60
        }
        #expect(store.state.isPairingCodeCopied)

        await store.send(.cancelPairingTapped) {
            $0.pairingCode = nil
            $0.pairingExpiresAt = nil
            $0.pairingSecondsRemaining = 0
            $0.isPairingCodeCopied = false
        }
        await store.receive(.pairingCancelled)
        #expect(await recorder.cancelPairingCount == 1)
    }
}

private actor RemotePasteboardRecorder {
    let result: Bool
    private(set) var values: [String] = []

    init(result: Bool) { self.result = result }

    nonisolated var client: RemotePasteboardClient {
        RemotePasteboardClient { value in
            await self.copy(value)
        }
    }

    private func copy(_ value: String) -> Bool {
        values.append(value)
        return result
    }
}

private actor RemotePasteboardGate {
    private var didStartCopy: CheckedContinuation<Void, Never>?
    private var response: CheckedContinuation<Bool, Never>?

    nonisolated var client: RemotePasteboardClient {
        RemotePasteboardClient { value in
            await self.copy(value)
        }
    }

    func waitForCopy() async {
        guard response == nil else { return }
        await withCheckedContinuation { didStartCopy = $0 }
    }

    func respond(succeeded: Bool) {
        response?.resume(returning: succeeded)
        response = nil
    }

    private func copy(_ value: String) async -> Bool {
        _ = value
        didStartCopy?.resume()
        didStartCopy = nil
        return await withCheckedContinuation { response = $0 }
    }
}

private actor RemoteAccessSettingsRecorder {
    let pairingWindow: PairingWindow
    private let eventStream: AsyncStream<RemoteHostEvent>
    private(set) var enabledValues: [Bool] = []
    private(set) var startedNames: [String] = []
    private(set) var displayNameValues: [String] = []
    private(set) var cancelPairingCount = 0
    private(set) var revokedDeviceIDs: [UUID] = []
    private let startError: RemoteAccessTestError?

    init(
        pairingWindow: PairingWindow = .init(code: "ABCDEFGH2345", expiresAt: .distantFuture),
        events: AsyncStream<RemoteHostEvent> = .finished,
        startError: RemoteAccessTestError? = nil
    ) {
        self.pairingWindow = pairingWindow
        self.eventStream = events
        self.startError = startError
    }

    nonisolated var preferences: RemoteAccessPreferencesClient {
        RemoteAccessPreferencesClient(
            load: { .init(isEnabled: false, displayName: "Test Mac") },
            setEnabled: { [weak self] value in await self?.recordEnabled(value) },
            setDisplayName: { [weak self] value in await self?.recordDisplayName(value) }
        )
    }

    nonisolated var host: RemoteHostClient {
        RemoteHostClient(
            start: { [weak self] configuration in
                try await self?.start(configuration)
            },
            stop: {},
            startPairing: { [pairingWindow] in pairingWindow },
            cancelPairing: { [weak self] in await self?.recordPairingCancellation() },
            revoke: { [weak self] id in await self?.recordRevocation(id) },
            pairedDevices: { [] },
            events: { [eventStream] in eventStream }
        )
    }

    private func recordEnabled(_ value: Bool) { enabledValues.append(value) }
    private func start(_ configuration: RemoteHostConfiguration) throws {
        if let startError { throw startError }
        startedNames.append(configuration.displayName)
    }
    private func recordDisplayName(_ value: String) { displayNameValues.append(value) }
    private func recordPairingCancellation() { cancelPairingCount += 1 }
    private func recordRevocation(_ id: UUID) { revokedDeviceIDs.append(id) }
}

private enum RemoteAccessTestError: LocalizedError, Sendable {
    case operationFailed

    var errorDescription: String? { "Test operation failed" }
}

private actor RemoteControllerHostRecorder {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    nonisolated var host: RemoteHostClient {
        RemoteHostClient(
            start: { [weak self] configuration in await self?.recordStart(configuration) },
            stop: { [weak self] in await self?.recordStop() },
            startPairing: { .init(code: "ABCDEFGH2345", expiresAt: .distantFuture) },
            cancelPairing: {},
            revoke: { _ in },
            pairedDevices: { [] },
            events: { .finished }
        )
    }

    func recordStart(_ configuration: RemoteHostConfiguration) {
        startCount += 1
    }

    func recordStop() {
        stopCount += 1
    }
}
