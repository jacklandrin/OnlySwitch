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

    @Test func unicodePasteNeverExpandsAndSkipsCombiningMarksAndSeparators() async {
        let store = TestStore(initialState: PairingFeature.State()) { PairingFeature() }
        await store.send(.codeChanged("ßa\u{301}—o0i1l b.c/d_e:f,g|h jkmnp")) {
            $0.code = "ABCDEFGHJKMN"
            $0.issue = nil
        }
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

    @Test(arguments: [UInt16(0), 1])
    func legacyMacRemainsVisibleButPairingIsDisabledWithUpgradeExplanation(minor: UInt16) async {
        let legacy = DiscoveredMac(
            id: macID,
            displayName: "Studio",
            endpoint: .hostPort(host: "studio.local", port: 9_000),
            protocolVersion: .init(major: 1, minor: minor)
        )
        var state = PairingFeature.State()
        state.discoveredMacs = [legacy]
        state.selectedMacID = macID
        state.code = "ABCDEFGHJKMN"

        #expect(state.discoveredMacs[id: macID] == legacy)
        #expect(state.selectedMacRequiresUpdate)
        #expect(state.canPair == false)
        #expect(state.helpText == "Update OnlySwitch on this Mac before pairing.")
    }

    @Test func preparedPairingBecomesNonDismissibleBeforeFinalizingAndDelegating() async {
        let mac = discovered()
        let paired = PairedMac(id: macID, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
        let transactionID = UUID()
        let prepared = PreparedPairing(
            transactionID: transactionID,
            mac: paired,
            catalog: .init(revision: 1, controls: [])
        )
        var state = PairingFeature.State()
        state.discoveredMacs = [mac]
        state.selectedMacID = macID
        state.code = "ABCDEFGHJKMN"
        let store = TestStore(initialState: state) {
            PairingFeature()
        } withDependencies: {
            $0.remoteConnection.preparePairing = { _, _, _ in prepared }
            $0.remoteConnection.finalizePairing = { id in
                #expect(id == transactionID)
                return paired
            }
        }

        await store.send(.pairTapped) {
            $0.isPairing = true
            $0.pairingTargetID = macID
            $0.issue = nil
            $0.pairingGeneration = 1
        }
        await store.receive(.prepared(1, macID, .success(prepared))) {
            $0.isFinalizing = true
            $0.preparedTransactionID = transactionID
            $0.finalizationAttempt = 1
        }
        await store.receive(.finalizeResponse(1, 1, transactionID, .success(paired))) {
            $0.isPairing = false
            $0.isFinalizing = false
            $0.pairingTargetID = nil
            $0.preparedTransactionID = nil
            $0.finalizationAttempt = 0
        }
        await store.receive(.delegate(.paired(paired)))
    }

    @Test func staleFinalizationAttemptCannotPublishOrReopenRetry() async {
        let transactionID = UUID()
        let paired = PairedMac(
            id: macID,
            displayName: "Studio",
            lastEndpointDescription: nil,
            lastConnectedAt: nil,
            requiresPairing: false
        )
        var state = PairingFeature.State()
        state.pairingGeneration = 4
        state.finalizationAttempt = 2
        state.isPairing = true
        state.isFinalizing = true
        state.preparedTransactionID = transactionID
        let store = TestStore(initialState: state) { PairingFeature() }

        await store.send(.finalizeResponse(4, 1, transactionID, .success(paired)))

        #expect(store.state.isFinalizing)
        #expect(store.state.preparedTransactionID == transactionID)
        #expect(store.state.issue == nil)
    }

    @Test func pairingExpiryHasSpecificRecoverableState() async {
        let store = configuredStore(error: RemoteProtocolError(code: .pairingExpired, message: "expired"))

        await store.send(.pairTapped) {
            $0.isPairing = true
            $0.pairingTargetID = macID
            $0.issue = nil
            $0.pairingGeneration = 1
        }
        await store.receive(.prepared(1, macID, .failure(.expired))) {
            $0.isPairing = false
            $0.pairingTargetID = nil
            $0.issue = .expired
        }
        #expect(store.state.issue == .expired)
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
            $0.pairingTargetID = macID
            $0.issue = nil
            $0.pairingGeneration = 1
        }
        await store.receive(.prepared(1, macID, .failure(value.1))) {
            $0.isPairing = false
            $0.pairingTargetID = nil
            $0.issue = value.1
        }
        #expect(store.state.issue == value.1)
    }

    @Test func selectionChangesAreIgnoredWhilePairing() async {
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let second = DiscoveredMac(id: secondID, displayName: "Laptop", endpoint: .hostPort(host: "laptop.local", port: 9001), protocolVersion: .current)
        var state = PairingFeature.State(); state.discoveredMacs = [discovered(), second]; state.selectedMacID = macID; state.pairingTargetID = macID; state.isPairing = true
        let store = TestStore(initialState: state) { PairingFeature() }
        await store.send(.selectMac(secondID))
        #expect(store.state.selectedMacID == macID)
        #expect(store.state.pairingTargetID == macID)
    }

    @Test func removingPairingTargetCancelsAndShowsUnavailableIssue() async {
        var state = PairingFeature.State(); state.discoveredMacs = [discovered()]; state.selectedMacID = macID; state.pairingTargetID = macID; state.isPairing = true; state.pairingGeneration = 4
        let store = TestStore(initialState: state) { PairingFeature() }
        await store.send(.discovery(0, .removed(macID))) {
            $0.discoveredMacs = []; $0.selectedMacID = nil; $0.pairingTargetID = nil; $0.isPairing = false; $0.pairingGeneration = 5; $0.issue = .selectedMacUnavailable
        }
    }

    @Test func stalePairingResponseAfterBackgroundIsIgnored() async {
        let paired = PairedMac(id: macID, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
        var state = PairingFeature.State()
        state.pairingGeneration = 7
        state.isPairing = true
        state.pairingTargetID = macID
        let store = TestStore(initialState: state) { PairingFeature() }

        await store.send(.foregroundChanged(false)) {
            $0.isForegrounded = false
            $0.isPairing = false
            $0.pairingTargetID = nil
            $0.discoveryGeneration = 1
            $0.pairingGeneration = 8
        }
        await store.send(.prepared(7, macID, .success(prepared(paired))))
        #expect(store.state.issue == nil)
    }

    @Test func pairingResponseForDifferentTargetIsIgnored() async {
        let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let paired = PairedMac(
            id: otherID,
            displayName: "Laptop",
            lastEndpointDescription: nil,
            lastConnectedAt: nil,
            requiresPairing: false
        )
        var state = PairingFeature.State()
        state.discoveredMacs = [discovered()]
        state.selectedMacID = macID
        state.pairingTargetID = macID
        state.isPairing = true
        state.pairingGeneration = 7
        let store = TestStore(initialState: state) { PairingFeature() }

        await store.send(.prepared(7, otherID, .success(prepared(paired))))

        #expect(store.state.isPairing)
        #expect(store.state.pairingTargetID == macID)
    }

    @Test func pairingResponseWithMismatchedPairedIdentityStopsWithoutDelegating() async {
        let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let paired = PairedMac(
            id: otherID,
            displayName: "Unexpected Mac",
            lastEndpointDescription: nil,
            lastConnectedAt: nil,
            requiresPairing: false
        )
        var state = PairingFeature.State()
        state.discoveredMacs = [discovered()]
        state.selectedMacID = macID
        state.pairingTargetID = macID
        state.isPairing = true
        state.pairingGeneration = 7
        let store = TestStore(initialState: state) { PairingFeature() }

        await store.send(.prepared(7, macID, .success(prepared(paired)))) {
            $0.isPairing = false
            $0.pairingTargetID = nil
            $0.issue = .identityMismatch
        }
    }

    @Test func preparedAfterPresentationWasInvalidatedIsAbortedWithoutPublication() async {
        let transactionID = UUID()
        let aborted = LockIsolated<[UUID?]>([])
        let candidate = PairedMac(
            id: macID,
            displayName: "Studio",
            lastEndpointDescription: nil,
            lastConnectedAt: nil,
            requiresPairing: false
        )
        var state = PairingFeature.State()
        state.pairingGeneration = 8
        let store = TestStore(initialState: state) { PairingFeature() } withDependencies: {
            $0.remoteConnection.abortPairing = { id in aborted.withValue { $0.append(id) } }
        }

        await store.send(.prepared(7, macID, .success(.init(
            transactionID: transactionID,
            mac: candidate,
            catalog: .init(revision: 1, controls: [])
        ))))
        await store.finish()

        #expect(aborted.value == [transactionID])
        #expect(store.state.preparedTransactionID == nil)
        #expect(store.state.isFinalizing == false)
    }

    @Test func codeChangesAreIgnoredWhilePairing() async {
        var state = PairingFeature.State()
        state.code = "ABCDEFGHJKMN"
        state.isPairing = true
        state.pairingTargetID = macID
        let store = TestStore(initialState: state) { PairingFeature() }

        await store.send(.codeChanged("23456789ABCD"))

        #expect(store.state.code == "ABCDEFGHJKMN")
    }

    @Test func presentationDismissalStopsDiscoveryWithoutAbsentChildAction() async throws {
        let (stream, continuation) = AsyncStream.makeStream(of: DiscoveryEvent.self)
        let (terminations, terminationContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingOldest(1))
        continuation.onTermination = { _ in terminationContinuation.yield(()) }
        var state = SettingsFeature.State(isSetupRequired: false); state.pairing = PairingFeature.State()
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.remoteConnection.discover = { stream }
            $0.remotePersistence.loadLayout = { _ in nil }
            $0.remotePersistence.loadCatalog = { _ in nil }
        }

        await store.send(.pairing(.presented(.task))) {
            $0.pairing?.discoveryGeneration = 1
            $0.pairing?.isDiscovering = true
        }
        await store.send(.pairing(.dismiss)) { $0.pairing = nil }
        var iterator = terminations.makeAsyncIterator()
        _ = try #require(await iterator.next())
        terminationContinuation.finish()
        await store.finish()
    }

    @Test func successfulPairingDismissesAndStopsDiscovery() async throws {
        let paired = PairedMac(
            id: macID,
            displayName: "Studio",
            lastEndpointDescription: nil,
            lastConnectedAt: nil,
            requiresPairing: false
        )
        let (stream, continuation) = AsyncStream.makeStream(of: DiscoveryEvent.self)
        let (terminations, terminationContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingOldest(1)
        )
        continuation.onTermination = { _ in terminationContinuation.yield(()) }
        var state = SettingsFeature.State(isSetupRequired: false)
        state.pairing = PairingFeature.State()
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.remoteConnection.discover = { stream }
            $0.remotePersistence.loadLayout = { _ in nil }
            $0.remotePersistence.loadCatalog = { _ in nil }
        }

        await store.send(.pairing(.presented(.task))) {
            $0.pairing?.discoveryGeneration = 1
            $0.pairing?.isDiscovering = true
        }
        await store.send(.pairing(.presented(.delegate(.paired(paired))))) {
            $0.pairing = nil
            $0.pairedMacs = [paired]
            $0.selectedMacID = paired.id
            $0.selectionGeneration = 1
        }
        await store.receive(.delegate(.paired(paired)))
        await store.receive(.selectedMacDataLoaded(1, paired.id, nil, nil))
        var iterator = terminations.makeAsyncIterator()
        _ = try #require(await iterator.next())
        continuation.finish()
        terminationContinuation.finish()
        await store.finish()
    }

    @Test func cancelDelegateDismissesAndCancelsInFlightPairing() async throws {
        let transportCancellations = LockIsolated(0)
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingOldest(1))
        let (gate, gateContinuation) = AsyncStream.makeStream(of: Void.self)
        let (cancelled, cancelledContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingOldest(1))
        var pairing = PairingFeature.State(); pairing.discoveredMacs = [discovered()]; pairing.selectedMacID = macID; pairing.code = "ABCDEFGHJKMN"
        var state = SettingsFeature.State(isSetupRequired: false); state.pairing = pairing
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.remoteConnection.abortPairing = { _ in transportCancellations.withValue { $0 += 1 } }
            $0.remoteConnection.preparePairing = { _, _, _ in
                startedContinuation.yield(())
                for await _ in gate { break }
                if Task.isCancelled {
                    cancelledContinuation.yield(())
                    throw CancellationError()
                }
                throw CancellationError()
            }
        }

        await store.send(.pairing(.presented(.pairTapped))) {
            $0.pairing?.isPairing = true
            $0.pairing?.pairingTargetID = macID
            $0.pairing?.issue = nil
            $0.pairing?.pairingGeneration = 1
        }
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())
        await store.send(.pairing(.presented(.cancelTapped))) {
            $0.pairing?.discoveryGeneration = 1; $0.pairing?.pairingGeneration = 2; $0.pairing?.pairingTargetID = nil; $0.pairing?.isPairing = false
        }
        await store.receive(.pairing(.presented(.delegate(.cancelled)))) { $0.pairing = nil }
        var cancelledIterator = cancelled.makeAsyncIterator()
        _ = try #require(await cancelledIterator.next())
        gateContinuation.finish()
        startedContinuation.finish()
        cancelledContinuation.finish()
        await store.finish()
        #expect(store.state.pairing == nil)
        #expect(transportCancellations.value == 0)
    }

    @Test func interactivePairingDismissCancelsTransportTransaction() async {
        let transportCancellations = LockIsolated(0)
        var state = SettingsFeature.State(isSetupRequired: false)
        state.pairing = PairingFeature.State()
        let store = TestStore(initialState: state) { SettingsFeature() } withDependencies: {
            $0.remoteConnection.abortPairing = { _ in transportCancellations.withValue { $0 += 1 } }
        }

        await store.send(.pairing(.dismiss)) { $0.pairing = nil }
        await store.finish()
        #expect(transportCancellations.value == 0)
    }

    @Test func reducerAdoptionMakesPairingPresentationNonDismissible() async {
        var pairing = PairingFeature.State()
        pairing.isPairing = true
        pairing.isFinalizing = true
        pairing.preparedTransactionID = UUID()
        #expect(pairing.isDismissDisabled)
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
            $0.remoteConnection.preparePairing = { _, _, _ in throw error }
        }
    }

    private func prepared(_ mac: PairedMac) -> PreparedPairing {
        .init(transactionID: UUID(), mac: mac, catalog: .init(revision: 1, controls: []))
    }
}
