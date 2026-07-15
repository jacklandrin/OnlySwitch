import ComposableArchitecture
import Foundation
import Network
import RemoteCore
import Testing
@testable import OnlySwitchRemote

@MainActor
struct PairingFeatureTests {
    private let macID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!

    @Test func discoveryUsesStableMacIdentityForUpdatesAndRemoval() async {
        let first = discovered(name: "Studio", port: 9_000)
        let updated = discovered(name: "Studio Mac", port: 9_001)
        var state = PairingFeature.State()
        state.discoveryGeneration = 4
        let store = TestStore(initialState: state) { PairingFeature() }

        await store.send(.discovery(4, .added(first))) {
            $0.discoveredMacs = [first]
        }
        await store.send(.selectMac(macID)) {
            $0.selectedMacID = macID
            $0.issue = nil
        }
        await store.send(.discovery(4, .added(updated))) {
            $0.discoveredMacs = [updated]
        }
        await store.send(.discovery(4, .removed(macID))) {
            $0.discoveredMacs = []
            $0.selectedMacID = nil
            $0.issue = .selectedMacUnavailable
        }
    }

    @Test func staleDiscoveryEventsAreIgnored() async {
        var state = PairingFeature.State()
        state.discoveryGeneration = 3
        let store = TestStore(initialState: state) { PairingFeature() }

        await store.send(.discovery(2, .added(discovered())))
        #expect(store.state.discoveredMacs.isEmpty)
    }

    @Test func completedDiscoveryOffersAWorkingRetry() async {
        let store = TestStore(initialState: PairingFeature.State()) {
            PairingFeature()
        } withDependencies: {
            $0.remoteConnection.discover = { AsyncStream { $0.finish() } }
        }

        await store.send(.task) {
            $0.discoveryGeneration = 1
            $0.isDiscovering = true
        }
        await store.receive(.discoveryFinished(1)) {
            $0.isDiscovering = false
        }
        await store.send(.retryDiscoveryTapped)
        await store.receive(.task) {
            $0.discoveryGeneration = 2
            $0.isDiscovering = true
        }
        await store.receive(.discoveryFinished(2)) {
            $0.isDiscovering = false
        }
    }

    @Test func codeNormalizationUsesExactUnambiguousAlphabetAndLength() async {
        let store = TestStore(initialState: PairingFeature.State()) { PairingFeature() }

        await store.send(.codeChanged("a0o1il-bcdefghjkmnpqrstuvwxyz23456789")) {
            $0.code = "ABCDEFGHJKMN"
            $0.issue = nil
        }
        #expect(store.state.code.count == 12)
        #expect(store.state.code.allSatisfy { "23456789ABCDEFGHJKMNPQRSTUVWXYZ".contains($0) })
    }

    @Test func pairingRequiresSelectedMacAndCompleteCode() async {
        var state = PairingFeature.State()
        state.code = "ABCDEFGHJKMN"
        let store = TestStore(initialState: state) { PairingFeature() }

        #expect(store.state.canPair == false)
        await store.send(.selectMac(macID))
        #expect(store.state.canPair == false)
        await store.send(.discovery(0, .added(discovered()))) {
            $0.discoveredMacs = [discovered()]
        }
        await store.send(.selectMac(macID)) {
            $0.selectedMacID = macID
            $0.issue = nil
        }
        #expect(store.state.canPair)
    }

    @Test func pairingSuccessDelegatesPairedMac() async {
        let mac = discovered()
        let paired = PairedMac(id: macID, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
        var state = PairingFeature.State()
        state.discoveredMacs = [mac]
        state.selectedMacID = macID
        state.code = "ABCDEFGHJKMN"
        let store = TestStore(initialState: state) {
            PairingFeature()
        } withDependencies: {
            $0.remoteConnection.pair = { _, _, _ in paired }
        }

        await store.send(.pairTapped) {
            $0.isPairing = true
            $0.issue = nil
            $0.pairingGeneration = 1
        }
        await store.receive(.pairingResponse(1, .success(paired))) {
            $0.isPairing = false
        }
        await store.receive(.delegate(.paired(paired)))
    }

    @Test func pairingExpiryHasSpecificRecoverableState() async {
        let store = configuredStore(error: RemoteProtocolError(code: .pairingExpired, message: "expired"))

        await store.send(.pairTapped) {
            $0.isPairing = true
            $0.issue = nil
            $0.pairingGeneration = 1
        }
        await store.receive(.pairingResponse(1, .failure(.expired))) {
            $0.isPairing = false
            $0.issue = .expired
        }
        #expect(store.state.issue?.message.contains("expired") == true)
    }

    @Test(arguments: [
        (RemoteProtocolError(code: .authenticationFailed, message: "Invalid code"), PairingIssue.invalidCode),
        (RemoteProtocolError(code: .authenticationFailed, message: "Credential revoked"), PairingIssue.revoked),
        (RemoteProtocolError(code: .pairingRateLimited, message: "Slow down"), PairingIssue.rateLimited),
        (RemoteProtocolError(code: .upgradeRequired, message: "Upgrade"), PairingIssue.upgradeRequired),
    ])
    func protocolFailuresMapToHelpfulStates(value: (RemoteProtocolError, PairingIssue)) async {
        let store = configuredStore(error: value.0)

        await store.send(.pairTapped) {
            $0.isPairing = true
            $0.issue = nil
            $0.pairingGeneration = 1
        }
        await store.receive(.pairingResponse(1, .failure(value.1))) {
            $0.isPairing = false
            $0.issue = value.1
        }
        #expect(store.state.issue?.helpText.isEmpty == false)
    }

    @Test func stalePairingResponseAfterBackgroundIsIgnored() async {
        let paired = PairedMac(id: macID, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
        var state = PairingFeature.State()
        state.pairingGeneration = 7
        state.isPairing = true
        let store = TestStore(initialState: state) { PairingFeature() }

        await store.send(.foregroundChanged(false)) {
            $0.isForegrounded = false
            $0.isPairing = false
            $0.discoveryGeneration = 1
            $0.pairingGeneration = 8
        }
        await store.send(.pairingResponse(7, .success(paired)))
        #expect(store.state.issue == nil)
    }

    @Test func dismissalStopsDiscovery() async throws {
        let (stream, continuation) = AsyncStream.makeStream(of: DiscoveryEvent.self)
        let (terminations, terminationContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingOldest(1))
        continuation.onTermination = { _ in terminationContinuation.yield(()) }
        let store = TestStore(initialState: PairingFeature.State()) {
            PairingFeature()
        } withDependencies: {
            $0.remoteConnection.discover = { stream }
        }

        await store.send(.task) {
            $0.discoveryGeneration = 1
            $0.isForegrounded = true
            $0.isDiscovering = true
        }
        await store.send(.onDisappear) {
            $0.discoveryGeneration = 2
            $0.pairingGeneration = 1
            $0.isDiscovering = false
            $0.isPairing = false
        }
        var iterator = terminations.makeAsyncIterator()
        _ = try #require(await iterator.next())
        terminationContinuation.finish()
        await store.finish()
    }

    @Test func dismissalCancelsInFlightPairingWithoutAnError() async throws {
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingOldest(1))
        let (gate, gateContinuation) = AsyncStream.makeStream(of: Void.self)
        let (cancelled, cancelledContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingOldest(1))
        var state = PairingFeature.State()
        state.discoveredMacs = [discovered()]
        state.selectedMacID = macID
        state.code = "ABCDEFGHJKMN"
        let store = TestStore(initialState: state) {
            PairingFeature()
        } withDependencies: {
            $0.remoteConnection.pair = { _, _, _ in
                startedContinuation.yield(())
                for await _ in gate { break }
                if Task.isCancelled {
                    cancelledContinuation.yield(())
                    throw CancellationError()
                }
                throw CancellationError()
            }
        }

        await store.send(.pairTapped) {
            $0.isPairing = true
            $0.issue = nil
            $0.pairingGeneration = 1
        }
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())
        await store.send(.onDisappear) {
            $0.discoveryGeneration = 1
            $0.pairingGeneration = 2
            $0.isPairing = false
        }
        var cancelledIterator = cancelled.makeAsyncIterator()
        _ = try #require(await cancelledIterator.next())
        gateContinuation.finish()
        startedContinuation.finish()
        cancelledContinuation.finish()
        await store.finish()
        #expect(store.state.issue == nil)
    }

    private func discovered(name: String = "Studio", port: UInt16 = 9_000) -> DiscoveredMac {
        DiscoveredMac(
            id: macID,
            displayName: name,
            endpoint: .hostPort(host: "studio.local", port: NWEndpoint.Port(rawValue: port)!),
            protocolVersion: .current
        )
    }

    private func configuredStore(error: RemoteProtocolError) -> TestStoreOf<PairingFeature> {
        var state = PairingFeature.State()
        state.discoveredMacs = [discovered()]
        state.selectedMacID = macID
        state.code = "ABCDEFGHJKMN"
        return TestStore(initialState: state) {
            PairingFeature()
        } withDependencies: {
            $0.remoteConnection.pair = { _, _, _ in throw error }
        }
    }
}
