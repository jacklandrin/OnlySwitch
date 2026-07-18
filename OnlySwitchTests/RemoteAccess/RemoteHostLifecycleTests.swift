import Foundation
import Network
import RemoteCore
import Testing
@testable import OnlySwitch

struct RemoteHostLifecycleTests {
    @Test
    func revokeWhileAuthenticationIsSuspendedCannotRegisterSession() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 2, maximumAuthenticatedSessions: 2)
        let generation = lifecycle.beginStart()
        let didListen = lifecycle.markListening(generation: generation)
        #expect(didListen)
        let sessionID = UUID()
        let deviceID = UUID()
        let didAccept = lifecycle.acceptPending(sessionID: sessionID, generation: generation)
        #expect(didAccept)

        let revokedSessions = lifecycle.revoke(deviceID: deviceID)
        let didAuthorize = lifecycle.authorize(
            sessionID: sessionID,
            deviceID: deviceID,
            generation: generation,
            credentialExists: true
        )
        #expect(revokedSessions.isEmpty)
        #expect(didAuthorize == false)
        #expect(lifecycle.authenticatedCount == 0)
    }

    @Test
    func stopWhileAuthenticationIsSuspendedInvalidatesGenerationAndClearsState() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 2, maximumAuthenticatedSessions: 2)
        let generation = lifecycle.beginStart()
        let didListen = lifecycle.markListening(generation: generation)
        #expect(didListen)
        let sessionID = UUID()
        let didAccept = lifecycle.acceptPending(sessionID: sessionID, generation: generation)
        #expect(didAccept)

        let sessionsToClose = lifecycle.stop()

        #expect(sessionsToClose == [sessionID])
        let didAuthorize = lifecycle.authorize(
            sessionID: sessionID,
            deviceID: UUID(),
            generation: generation,
            credentialExists: true
        )
        #expect(didAuthorize == false)
        #expect(lifecycle.pendingCount == 0)
        #expect(lifecycle.authenticatedCount == 0)
    }

    @Test
    func pendingAndAuthenticatedCapsAreEnforcedIndependently() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 1, maximumAuthenticatedSessions: 1)
        let generation = lifecycle.beginStart()
        let didListen = lifecycle.markListening(generation: generation)
        #expect(didListen)
        let first = UUID()
        let second = UUID()
        let acceptedFirst = lifecycle.acceptPending(sessionID: first, generation: generation)
        let acceptedSecondWhileFull = lifecycle.acceptPending(sessionID: second, generation: generation)
        let authorizedFirst = lifecycle.authorize(
            sessionID: first,
            deviceID: UUID(),
            generation: generation,
            credentialExists: true
        )
        let acceptedSecond = lifecycle.acceptPending(sessionID: second, generation: generation)
        let authorizedSecond = lifecycle.authorize(
            sessionID: second,
            deviceID: UUID(),
            generation: generation,
            credentialExists: true
        )
        #expect(acceptedFirst)
        #expect(acceptedSecondWhileFull == false)
        #expect(authorizedFirst)
        #expect(acceptedSecond)
        #expect(authorizedSecond == false)
    }

    @Test
    func staleListenerCallbacksCannotChangeNewLifecycle() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 1, maximumAuthenticatedSessions: 1)
        let staleGeneration = lifecycle.beginStart()
        _ = lifecycle.stop()
        let currentGeneration = lifecycle.beginStart()

        let staleReady = lifecycle.markListening(generation: staleGeneration)
        let currentReady = lifecycle.markListening(generation: currentGeneration)
        let staleFailureSessions = lifecycle.fail(generation: staleGeneration)
        #expect(staleReady == false)
        #expect(currentReady)
        #expect(staleFailureSessions.isEmpty)
        #expect(lifecycle.isListening(generation: currentGeneration))
    }

    @Test
    func listenerFailureTearsDownCurrentGenerationExactlyOnce() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 2, maximumAuthenticatedSessions: 2)
        let generation = lifecycle.beginStart()
        let didListen = lifecycle.markListening(generation: generation)
        #expect(didListen)
        let sessionID = UUID()
        let didAccept = lifecycle.acceptPending(sessionID: sessionID, generation: generation)
        #expect(didAccept)

        let firstFailureSessions = lifecycle.fail(generation: generation)
        let secondFailureSessions = lifecycle.fail(generation: generation)
        #expect(firstFailureSessions == [sessionID])
        #expect(secondFailureSessions.isEmpty)
        #expect(lifecycle.isActive(generation: generation) == false)
    }

    @Test
    func endingAStaleSessionAlwaysRemovesPendingAndAuthenticatedMappings() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 2, maximumAuthenticatedSessions: 2)
        let generation = lifecycle.beginStart()
        let didListen = lifecycle.markListening(generation: generation)
        #expect(didListen)
        let sessionID = UUID()
        let didAccept = lifecycle.acceptPending(sessionID: sessionID, generation: generation)
        let didAuthorize = lifecycle.authorize(
            sessionID: sessionID,
            deviceID: UUID(),
            generation: generation,
            credentialExists: true
        )
        #expect(didAccept)
        #expect(didAuthorize)

        let firstEnd = lifecycle.end(sessionID: sessionID)
        let secondEnd = lifecycle.end(sessionID: sessionID)
        #expect(firstEnd)
        #expect(secondEnd == false)
        #expect(lifecycle.pendingCount == 0)
        #expect(lifecycle.authenticatedCount == 0)
    }

    @Test
    func revocationAfterPairingAuthorizationPreventsTombstoneClear() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 1, maximumAuthenticatedSessions: 1)
        let generation = lifecycle.beginStart()
        let didListen = lifecycle.markListening(generation: generation)
        #expect(didListen)
        let deviceID = UUID()
        let pairingEpoch = lifecycle.pairingEpoch(for: deviceID)

        _ = lifecycle.revoke(deviceID: deviceID)

        let didAllowRepair = lifecycle.allowRepairedDevice(
            deviceID,
            pairingEpoch: pairingEpoch,
            generation: generation
        )
        #expect(didAllowRepair == false)
    }

    @Test
    func epochCapturedBeforeProofConsumptionRejectsLaterRevocation() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 1, maximumAuthenticatedSessions: 1)
        let generation = lifecycle.beginStart()
        let didListen = lifecycle.markListening(generation: generation)
        #expect(didListen)
        let deviceID = UUID()

        let epochCapturedBeforeProofConsumption = lifecycle.pairingEpoch(for: deviceID)
        _ = lifecycle.revoke(deviceID: deviceID)

        let didAllowRepair = lifecycle.allowRepairedDevice(
            deviceID,
            pairingEpoch: epochCapturedBeforeProofConsumption,
            generation: generation
        )
        #expect(didAllowRepair == false)
    }
}

struct RemoteCredentialReplacementTests {
    @Test
    func abortedRepairRestoresExistingCredentialWithoutClearingTombstone() async throws {
        let store = RemoteCredentialStore.inMemory()
        let deviceID = UUID()
        let original = Self.device(id: deviceID, byte: 1)
        let replacement = Self.device(id: deviceID, byte: 2)
        let lifecycle = PairingLifecycleHarness()
        try await store.save(original)
        await lifecycle.revoke(deviceID)

        let transaction = try await RemotePairingTransaction.begin(
            record: replacement,
            credentialStore: store,
            pairingSnapshot: { await lifecycle.snapshot(for: $0) },
            consumePairing: { true }
        )
        #expect(await transaction.validate { await lifecycle.validate($0) })
        #expect(await lifecycle.isRevoked(deviceID))

        await transaction.rollback(
            credentialStore: store,
            rollbackPairingState: { await lifecycle.rollback($0) },
            currentEpoch: { await lifecycle.epoch(for: $0) }
        )

        #expect(try await store.load(deviceID) == original)
        #expect(await lifecycle.isRevoked(deviceID))
        #expect(await lifecycle.canAuthenticate(deviceID) == false)
    }

    @Test
    func successfulRepairClearsTombstoneOnlyAtCommit() async throws {
        let store = RemoteCredentialStore.inMemory()
        let deviceID = UUID()
        let original = Self.device(id: deviceID, byte: 1)
        let replacement = Self.device(id: deviceID, byte: 2)
        let lifecycle = PairingLifecycleHarness()
        try await store.save(original)
        await lifecycle.revoke(deviceID)

        let transaction = try await RemotePairingTransaction.begin(
            record: replacement,
            credentialStore: store,
            pairingSnapshot: { await lifecycle.snapshot(for: $0) },
            consumePairing: { true }
        )

        #expect(await transaction.validate { await lifecycle.validate($0) })
        #expect(await lifecycle.isRevoked(deviceID))
        #expect(await transaction.commit { await lifecycle.commit($0) })
        #expect(await lifecycle.isRevoked(deviceID) == false)
        #expect(try await store.load(deviceID) == replacement)
    }

    @Test
    func newRevocationEpochNeverRestoresPriorCredentialOrClearsTombstone() async throws {
        let store = RemoteCredentialStore.inMemory()
        let deviceID = UUID()
        let original = Self.device(id: deviceID, byte: 1)
        let replacement = Self.device(id: deviceID, byte: 2)
        let lifecycle = PairingLifecycleHarness()
        try await store.save(original)

        let transaction = try await RemotePairingTransaction.begin(
            record: replacement,
            credentialStore: store,
            pairingSnapshot: { await lifecycle.snapshot(for: $0) },
            consumePairing: {
                await lifecycle.revoke(deviceID)
                return true
            }
        )

        #expect(await transaction.validate { await lifecycle.validate($0) } == false)
        await transaction.rollback(
            credentialStore: store,
            rollbackPairingState: { await lifecycle.rollback($0) },
            currentEpoch: { await lifecycle.epoch(for: $0) }
        )

        #expect(try await store.load(deviceID) == nil)
        #expect(await lifecycle.isRevoked(deviceID))
    }

    @Test
    func rollbackUsesCredentialCapturedBeforePairingProofConsumption() async throws {
        let store = RemoteCredentialStore.inMemory()
        let deviceID = UUID()
        let original = Self.device(id: deviceID, byte: 1)
        let intervening = Self.device(id: deviceID, byte: 2)
        let replacement = Self.device(id: deviceID, byte: 3)
        let lifecycle = PairingLifecycleHarness()
        try await store.save(original)

        let transaction = try await RemotePairingTransaction.begin(
            record: replacement,
            credentialStore: store,
            pairingSnapshot: { await lifecycle.snapshot(for: $0) },
            consumePairing: {
                try? await store.save(intervening)
                return true
            }
        )
        await transaction.rollback(
            credentialStore: store,
            rollbackPairingState: { await lifecycle.rollback($0) },
            currentEpoch: { await lifecycle.epoch(for: $0) }
        )

        #expect(try await store.load(deviceID) == original)
    }

    private static func device(id: UUID, byte: UInt8) -> PairedRemoteDevice {
        .init(
            id: id,
            name: "Test iPhone",
            credential: Data(repeating: byte, count: 32),
            createdAt: .now,
            lastConnectedAt: nil
        )
    }
}

struct RemoteRevocationCleanupTests {
    @Test
    func runtimeCleanupCompletesBeforePersistenceFailureIsReported() async {
        let sessionID = UUID()
        let events = StringEventProbe()

        await #expect(throws: RevocationTestError.failed) {
            try await RemoteHost.performRevocationCleanup(
                sessionIDs: [sessionID],
                removeSubscription: { _ in await events.record("remove") },
                closePeer: { _ in await events.record("close") },
                deleteCredential: {
                    await events.record("delete")
                    throw RevocationTestError.failed
                }
            )
        }

        #expect(await events.values == ["remove", "close", "delete"])
    }

    @Test func stalledLiveNotificationIsClosedBeforeCredentialDeletionContinues() async throws {
        let sessionID = UUID()
        let stalledSend = TestGate()
        let events = StringEventProbe()

        try await RemoteHost.performRevocationCleanup(
            sessionIDs: [sessionID],
            removeSubscription: { _ in },
            closePeer: { _ in
                await RemotePeerSession.notifyRevocation(
                    deadline: .zero,
                    send: { await stalledSend.wait() },
                    close: {
                        await events.record("force-close")
                        await stalledSend.open()
                    }
                )
            },
            deleteCredential: { await events.record("delete") }
        )

        #expect(await events.values == ["force-close", "delete"])
    }
}

struct RemoteHostStartFailureTests {
    @Test(.timeLimit(.minutes(1)))
    func listenerCreationFailureCleansLifecycleAndPublishesFailure() async {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let host = RemoteHost.testing(
            catalog: [],
            router: router,
            pairingCode: "123456",
            listenerFactory: { _ in throw StartTestError.listener }
        )
        var events = host.events.makeAsyncIterator()

        await #expect(throws: StartTestError.listener) {
            try await host.start(configuration: .init(displayName: "Test"))
        }

        var failure: HostStatus?
        while let event = await events.next() {
            if case let .statusChanged(status) = event, case .failed = status {
                failure = status
                break
            }
        }
        #expect(failure == .failed("Remote access could not start"))
        #expect(await host.hasOwnedListener == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func installationIdentityFailureCancelsOwnedListenerAndPublishesFailure() async {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let host = RemoteHost.testing(
            catalog: [],
            router: router,
            pairingCode: "123456",
            installationIDProvider: { throw StartTestError.identity }
        )
        var events = host.events.makeAsyncIterator()

        await #expect(throws: StartTestError.identity) {
            try await host.start(configuration: .init(displayName: "Test"))
        }

        var failure: HostStatus?
        while let event = await events.next() {
            if case let .statusChanged(status) = event, case .failed = status {
                failure = status
                break
            }
        }
        #expect(failure == .failed("Remote access could not start"))
        #expect(await host.hasOwnedListener == false)
    }
}

struct RemotePairingWindowTests {
    @Test
    func pairingCodeIsSingleUse() async {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let host = RemoteHost.testing(catalog: [], router: router, pairingCode: "123456")
        _ = await host.startPairing()

        #expect(await host.consumePairing(code: "123456"))
        #expect(await host.consumePairing(code: "123456") == false)
    }

    @Test
    func pairingWindowExpires() async {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let host = RemoteHost.testing(catalog: [], router: router, pairingCode: "123456")
        _ = await host.startPairing(expiresAt: .distantPast)

        #expect(await host.activePairingWindow() == nil)
        #expect(await host.consumePairing(code: "123456") == false)
    }

    @Test
    func fifthPairingFailureClosesWindow() async {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let host = RemoteHost.testing(catalog: [], router: router, pairingCode: "123456")
        _ = await host.startPairing()

        for _ in 0..<5 { await host.recordPairingFailure() }

        #expect(await host.activePairingWindow() == nil)
    }
}

struct RemotePeerDeadlineTests {
    @Test
    func timeoutRejectsAStalledOperation() async {
        await #expect(throws: CancellationError.self) {
            try await RemotePeerSession.withTimeout(.zero) {
                try await Task.sleep(for: .seconds(3_600))
            }
        }
    }
}

struct RemoteCatalogMonitorTests {
    @Test(.timeLimit(.minutes(1)))
    func overlappingRefreshCannotPublishOlderCatalogAsNewerRevision() async throws {
        let provider = SuspendedCatalogProvider(initial: [.darkModeDescriptor])
        let monitor = RemoteCatalogMonitor(provider: await provider.provider, observeNotifications: false)

        #expect(try await monitor.current().revision == 1)
        async let first = monitor.requestRefresh()
        async let second = monitor.requestRefresh()

        await provider.waitUntilSuspendedCalls(1)
        await provider.resumeOldest(with: [.hideDesktopDescriptor])
        await provider.waitUntilSuspendedCalls(2)
        await provider.resumeNewest(with: [.muteDescriptor])
        _ = try await (first, second)

        let current = try await monitor.current()
        #expect(current.controls == [.muteDescriptor])
        #expect(current.revision == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func notificationsCoalesceIntoOneFollowUp() async throws {
        let provider = SuspendedCatalogProvider(initial: [.darkModeDescriptor])
        let coalesced = CoalescedRefreshProbe()
        let monitor = RemoteCatalogMonitor(
            provider: await provider.provider,
            pollInterval: .hours(1),
            debounceInterval: .zero,
            pollWait: { try await Task.sleep(for: $0) },
            refreshCoalescedObserver: { coalesced.record() }
        )
        _ = try await monitor.current()
        await monitor.setAuthenticatedSessionCount(1)

        let first = Task { try await monitor.requestRefresh() }
        await provider.waitUntilSuspendedCalls(1)
        await monitor.scheduleDebouncedRefresh()
        await coalesced.waitUntilCount(1)
        await monitor.scheduleDebouncedRefresh()
        await coalesced.waitUntilCount(2)
        await provider.resumeOldest(with: [.hideDesktopDescriptor])
        await provider.waitUntilSuspendedCalls(2)
        await provider.resumeNewest(with: [.muteDescriptor])
        _ = try await first.value

        #expect(await provider.suspendedCallCount == 2)
        #expect(try await monitor.current().controls == [.muteDescriptor])
        await monitor.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func transientProviderFailureRecoversOnNextTick() async throws {
        let source = CatalogSource([Self.descriptor(id: .init(kind: .builtIn, value: "1"), available: true)])
        let (ticks, continuation) = AsyncStream.makeStream(of: Void.self)
        let monitor = RemoteCatalogMonitor(
            provider: await source.provider,
            observeNotifications: false,
            pollWait: { _ in
                for await _ in ticks { return }
                throw CancellationError()
            }
        )
        _ = try await monitor.current()
        await source.failNextLoad()
        await monitor.setAuthenticatedSessionCount(1)
        continuation.yield(())
        await source.waitUntilCalls(2)

        await source.set([Self.descriptor(id: .init(kind: .builtIn, value: "1"), available: false)])
        continuation.yield(())
        await source.waitUntilCalls(3)

        #expect(try await monitor.current().revision == 2)
        continuation.finish()
        await monitor.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func rapidStopStartCreatesOnePoller() async throws {
        let source = CatalogSource([])
        let (ticks, continuation) = AsyncStream.makeStream(of: Void.self)
        let monitor = RemoteCatalogMonitor(
            provider: await source.provider,
            observeNotifications: false,
            pollWait: { _ in
                for await _ in ticks { return }
                throw CancellationError()
            }
        )
        _ = try await monitor.current()
        await monitor.setAuthenticatedSessionCount(1)
        continuation.yield(())
        await source.waitUntilCalls(2)
        await monitor.setAuthenticatedSessionCount(0)
        await monitor.setAuthenticatedSessionCount(1)
        continuation.yield(())
        await source.waitUntilCalls(3)

        #expect(await source.catalogCalls == 3)
        continuation.finish()
        await monitor.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func restartWhileOldPollerIsStoppingPreservesOnlyTheNewPoller() async throws {
        let source = CatalogSource([])
        let waits = PollWaitGate()
        let monitor = RemoteCatalogMonitor(
            provider: await source.provider,
            observeNotifications: false,
            pollWait: { _ in try await waits.wait() }
        )
        _ = try await monitor.current()
        await monitor.setAuthenticatedSessionCount(1)
        await waits.waitUntilStarted(1)

        let stopping = Task { await monitor.setAuthenticatedSessionCount(0) }
        await waits.waitUntilCancelled(1)
        await monitor.setAuthenticatedSessionCount(1)
        await waits.waitUntilStarted(2)

        waits.resumeOldest()
        await stopping.value
        waits.resumeOldest()
        await source.waitUntilCalls(2)
        await waits.waitUntilStarted(3)

        #expect(await source.catalogCalls == 2)
        #expect(waits.pendingCount == 1)

        let finalStop = Task { await monitor.stop() }
        await waits.waitUntilCancelled(2)
        waits.resumeAll()
        await finalStop.value
    }

    @Test(.timeLimit(.minutes(1)))
    func oldCancelledRefreshCannotClearItsReplacement() async throws {
        let provider = CancellationAwareCatalogProvider(
            leading: [[.darkModeDescriptor]],
            first: [.hideDesktopDescriptor],
            subsequent: [.muteDescriptor]
        )
        let monitor = RemoteCatalogMonitor(
            provider: provider.provider,
            observeNotifications: false
        )
        #expect(try await monitor.current().controls == [.darkModeDescriptor])
        let oldRefresh = Task { try await monitor.requestRefresh() }
        await provider.waitUntilFirstStarted()

        let stopping = Task { await monitor.setAuthenticatedSessionCount(0) }
        await provider.waitUntilFirstCancelled()
        let replacement = try #require(try await monitor.requestRefresh())
        provider.resumeFirst()
        await stopping.value
        await #expect(throws: CancellationError.self) { try await oldRefresh.value }

        #expect(replacement == .init(revision: 2, controls: [.muteDescriptor]))
        #expect(try await monitor.current() == replacement)
        #expect(provider.callCount == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func stopAwaitsObservationTasks() async throws {
        let source = CatalogSource([])
        let started = TestSignal()
        let monitor = RemoteCatalogMonitor(
            provider: await source.provider,
            debounceInterval: .hours(1),
            pollWait: { _ in
                await started.signal()
                try await Task.sleep(for: .hours(1))
            }
        )
        _ = try await monitor.current()
        await monitor.setAuthenticatedSessionCount(1)
        await started.wait()
        await monitor.scheduleDebouncedRefresh()

        await monitor.stop()
        #expect(await source.catalogCalls == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func stopDuringInitialRefreshCannotRestoreClearedSnapshot() async throws {
        let provider = CancellationAwareCatalogProvider(
            first: [.darkModeDescriptor],
            subsequent: [.muteDescriptor]
        )
        let monitor = RemoteCatalogMonitor(
            provider: provider.provider,
            observeNotifications: false
        )
        let refresh = Task { try await monitor.requestRefresh() }
        await provider.waitUntilFirstStarted()

        let stopping = Task { await monitor.stop() }
        await provider.waitUntilFirstCancelled()
        provider.resumeFirst()
        await stopping.value
        await #expect(throws: CancellationError.self) { try await refresh.value }

        let restarted = try await monitor.current()
        #expect(restarted == .init(revision: 1, controls: [.muteDescriptor]))
        #expect(provider.callCount == 2)
    }

    @Test
    func lazySnapshotStartsAtOneAndOrderOnlyChangesDoNotAdvanceRevision() async throws {
        let source = CatalogSource([
            Self.descriptor(id: .init(kind: .shortcut, value: "B"), available: true),
            Self.descriptor(id: .init(kind: .shortcut, value: "A"), available: true),
        ])
        let monitor = RemoteCatalogMonitor(provider: await source.provider)

        let first = try await monitor.current()
        #expect(first.revision == 1)
        #expect(first.controls.map(\.id.value) == ["A", "B"])

        await source.set(first.controls.reversed())
        #expect(try await monitor.refresh() == nil)
        #expect(try await monitor.current().revision == 1)
    }

    @Test
    func structuralChangeAdvancesRevisionOnceAndPublishesIt() async throws {
        let id = RemoteControlID(kind: .builtIn, value: "2")
        let source = CatalogSource([Self.descriptor(id: id, available: true)])
        let monitor = RemoteCatalogMonitor(provider: await source.provider)
        var changes = monitor.changes.makeAsyncIterator()
        _ = try await monitor.current()

        await source.set([Self.descriptor(id: id, available: false)])
        let changed = try #require(try await monitor.refresh())
        #expect(changed.revision == 2)
        #expect(await changes.next() == changed)
        #expect(try await monitor.refresh() == nil)
    }

    @Test
    func pollingRunsOnlyWhileAuthenticatedSessionsExist() async throws {
        let source = CatalogSource([])
        let (ticks, tickContinuation) = AsyncStream.makeStream(of: Void.self)
        let monitor = RemoteCatalogMonitor(
            provider: await source.provider,
            observeNotifications: false,
            pollWait: { _ in
                for await _ in ticks { return }
                throw CancellationError()
            }
        )
        _ = try await monitor.current()
        #expect(await source.catalogCalls == 1)

        await monitor.setAuthenticatedSessionCount(1)
        tickContinuation.yield(())
        await source.waitUntilCalls(2)
        let authenticatedCalls = await source.catalogCalls
        #expect(authenticatedCalls == 2)

        await monitor.setAuthenticatedSessionCount(0)
        tickContinuation.yield(())
        #expect(await source.catalogCalls == authenticatedCalls)
        tickContinuation.finish()
    }

    private static func descriptor(
        id: RemoteControlID,
        available: Bool
    ) -> RemoteControlDescriptor {
        .init(
            id: id,
            title: id.value,
            behavior: .switch,
            icon: .systemSymbol("switch.2"),
            isAvailable: available,
            unavailableReason: available ? nil : "Unavailable",
            isDestructive: false,
            supportsStatus: true,
            supportsSecondaryInformation: false
        )
    }
}

private actor CatalogSource {
    private var controls: [RemoteControlDescriptor]
    private(set) var catalogCalls = 0
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var nextLoadError: (any Error)?

    init(_ controls: [RemoteControlDescriptor]) { self.controls = controls }

    var provider: RemoteCatalogProvider {
        RemoteCatalogProvider(
            catalog: { [weak self] in try await self?.load() ?? [] },
            status: { id, revision in
                RemoteControlStatus(
                    id: id,
                    isAvailable: true,
                    unavailableReason: nil,
                    isOn: nil,
                    secondaryInformation: nil,
                    isProcessing: false,
                    revision: revision,
                    updatedAt: .now
                )
            }
        )
    }

    func set<S: Sequence>(_ controls: S) where S.Element == RemoteControlDescriptor {
        self.controls = Array(controls)
    }

    func failNextLoad() { nextLoadError = RevocationTestError.failed }

    private func load() throws -> [RemoteControlDescriptor] {
        catalogCalls += 1
        let ready = callWaiters.filter { catalogCalls >= $0.0 }
        callWaiters.removeAll { catalogCalls >= $0.0 }
        ready.forEach { $0.1.resume() }
        if let nextLoadError {
            self.nextLoadError = nil
            throw nextLoadError
        }
        return controls
    }

    func waitUntilCalls(_ count: Int) async {
        guard catalogCalls < count else { return }
        await withCheckedContinuation { callWaiters.append((count, $0)) }
    }
}

private actor SuspendedCatalogProvider {
    private var initial: [RemoteControlDescriptor]?
    private var suspendedCalls = 0
    private var suspendedCallWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var continuations: [CheckedContinuation<[RemoteControlDescriptor], Error>] = []

    init(initial: [RemoteControlDescriptor]) {
        self.initial = initial
    }

    var suspendedCallCount: Int { suspendedCalls }

    var provider: RemoteCatalogProvider {
        RemoteCatalogProvider(
            catalog: { [weak self] in try await self?.load() ?? [] },
            status: { id, revision in
                RemoteControlStatus(
                    id: id,
                    isAvailable: true,
                    unavailableReason: nil,
                    isOn: nil,
                    secondaryInformation: nil,
                    isProcessing: false,
                    revision: revision,
                    updatedAt: .now
                )
            }
        )
    }

    func waitUntilSuspendedCalls(_ count: Int) async {
        guard suspendedCalls < count else { return }
        await withCheckedContinuation { suspendedCallWaiters.append((count, $0)) }
    }

    func resumeNewest(with controls: [RemoteControlDescriptor]) {
        continuations.removeLast().resume(returning: controls)
    }

    func resumeOldest(with controls: [RemoteControlDescriptor]) {
        continuations.removeFirst().resume(returning: controls)
    }

    private func load() async throws -> [RemoteControlDescriptor] {
        if let initial {
            self.initial = nil
            return initial
        }
        suspendedCalls += 1
        let waiters = suspendedCallWaiters.filter { suspendedCalls >= $0.0 }.map(\.1)
        suspendedCallWaiters.removeAll { suspendedCalls >= $0.0 }
        waiters.forEach { $0.resume() }
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }
}

private final class CoalescedRefreshProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func record() {
        let ready = lock.withLock {
            count += 1
            let ready = waiters.filter { count >= $0.0 }.map(\.1)
            waiters.removeAll { count >= $0.0 }
            return ready
        }
        ready.forEach { $0.resume() }
    }

    func waitUntilCount(_ expected: Int) async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                guard count < expected else { return true }
                waiters.append((expected, continuation))
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }
}

private final class PollWaitGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waits: [CheckedContinuation<Void, Never>] = []
    private var startedCount = 0
    private var cancelledCount = 0
    private var startedWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cancelledWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    var pendingCount: Int { lock.withLock { waits.count } }

    func wait() async throws {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let ready: [CheckedContinuation<Void, Never>] = lock.withLock {
                    waits.append(continuation)
                    startedCount += 1
                    let ready = startedWaiters.filter { startedCount >= $0.0 }.map(\.1)
                    startedWaiters.removeAll { startedCount >= $0.0 }
                    return ready
                }
                ready.forEach { $0.resume() }
            }
        } onCancel: {
            let ready: [CheckedContinuation<Void, Never>] = self.lock.withLock {
                self.cancelledCount += 1
                let ready = self.cancelledWaiters.filter { self.cancelledCount >= $0.0 }.map(\.1)
                self.cancelledWaiters.removeAll { self.cancelledCount >= $0.0 }
                return ready
            }
            ready.forEach { $0.resume() }
        }
        try Task.checkCancellation()
    }

    func waitUntilStarted(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                guard startedCount < count else { return true }
                startedWaiters.append((count, continuation))
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func waitUntilCancelled(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                guard cancelledCount < count else { return true }
                cancelledWaiters.append((count, continuation))
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func resumeOldest() {
        lock.withLock { waits.isEmpty ? nil : waits.removeFirst() }?.resume()
    }

    func resumeAll() {
        let continuations = lock.withLock {
            defer { waits.removeAll() }
            return waits
        }
        continuations.forEach { $0.resume() }
    }
}

private final class CancellationAwareCatalogProvider: @unchecked Sendable {
    private let lock = NSLock()
    private let first: [RemoteControlDescriptor]
    private let subsequent: [RemoteControlDescriptor]
    private let leading: [[RemoteControlDescriptor]]
    private var calls = 0
    private var firstContinuation: CheckedContinuation<Void, Never>?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelledWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstCancelled = false

    init(
        leading: [[RemoteControlDescriptor]] = [],
        first: [RemoteControlDescriptor],
        subsequent: [RemoteControlDescriptor]
    ) {
        self.leading = leading
        self.first = first
        self.subsequent = subsequent
    }

    var callCount: Int { lock.withLock { calls } }

    var provider: RemoteCatalogProvider {
        RemoteCatalogProvider(
            catalog: { [weak self] in try await self?.load() ?? [] },
            status: { id, revision in
                RemoteControlStatus(
                    id: id,
                    isAvailable: true,
                    unavailableReason: nil,
                    isOn: nil,
                    secondaryInformation: nil,
                    isProcessing: false,
                    revision: revision,
                    updatedAt: .now
                )
            }
        )
    }

    func waitUntilFirstStarted() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                guard calls == 0 else { return true }
                startedWaiters.append(continuation)
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func waitUntilFirstCancelled() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                guard firstCancelled == false else { return true }
                cancelledWaiters.append(continuation)
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func resumeFirst() {
        lock.withLock {
            defer { firstContinuation = nil }
            return firstContinuation
        }?.resume()
    }

    private func load() async throws -> [RemoteControlDescriptor] {
        let call = lock.withLock {
            calls += 1
            return calls
        }
        if call <= leading.count { return leading[call - 1] }
        guard call == leading.count + 1 else { return subsequent }

        try await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let waiters = lock.withLock {
                    firstContinuation = continuation
                    defer { startedWaiters.removeAll() }
                    return startedWaiters
                }
                waiters.forEach { $0.resume() }
            }
        } onCancel: {
            let waiters = self.lock.withLock {
                self.firstCancelled = true
                defer { self.cancelledWaiters.removeAll() }
                return self.cancelledWaiters
            }
            waiters.forEach { $0.resume() }
        }
        try Task.checkCancellation()
        return first
    }
}

private extension RemoteControlDescriptor {
    static var darkModeDescriptor: Self { descriptor(kind: .builtIn, value: "darkMode") }
    static var muteDescriptor: Self { descriptor(kind: .builtIn, value: "mute") }
    static var hideDesktopDescriptor: Self { descriptor(kind: .builtIn, value: "hideDesktop") }

    private static func descriptor(kind: RemoteControlKind, value: String) -> Self {
        .init(
            id: .init(kind: kind, value: value),
            title: value,
            behavior: .switch,
            icon: .systemSymbol("switch.2"),
            isAvailable: true,
            unavailableReason: nil,
            isDestructive: false,
            supportsStatus: true,
            supportsSecondaryInformation: false
        )
    }
}

struct RemoteStatusSchedulerTests {
    @Test
    func rejectsUnknownAndOversizedSubscriptionsWithoutCreatingRefreshes() async throws {
        let knownID = RemoteControlID(kind: .builtIn, value: "2")
        let descriptor = Self.descriptor(id: knownID)
        let calls = StatusCallProbe()
        let provider = RemoteCatalogProvider(
            catalog: { [descriptor] },
            status: { id, revision in
                await calls.record(id)
                return Self.status(id: id, revision: revision)
            }
        )
        let scheduler = RemoteStatusScheduler(provider: provider, observeNotifications: false)

        await #expect(throws: RemoteProtocolError.self) {
            try await scheduler.update(sessionID: UUID(), ids: [.init(kind: .builtIn, value: "999")]) { _ in }
        }
        let tooMany = Set((0...RemoteStatusScheduler.maximumSubscriptionsPerSession).map {
            RemoteControlID(kind: .shortcut, value: "Shortcut \($0)")
        })
        await #expect(throws: RemoteProtocolError.self) {
            try await scheduler.update(sessionID: UUID(), ids: tooMany) { _ in }
        }
        #expect(await calls.count == 0)
    }

    @Test
    func immediateRefreshIsCoalescedAcrossSubscribersAndUnsubscribeCancelsWork() async throws {
        let id = RemoteControlID(kind: .builtIn, value: "2")
        let descriptor = Self.descriptor(id: id)
        let calls = StatusCallProbe()
        let provider = RemoteCatalogProvider(
            catalog: { [descriptor] },
            status: { id, revision in
                await calls.record(id)
                return Self.status(id: id, revision: revision)
            }
        )
        let scheduler = RemoteStatusScheduler(
            provider: provider,
            interval: .seconds(3_600),
            observeNotifications: false
        )
        let first = UUID()
        let second = UUID()

        try await scheduler.update(sessionID: first, ids: [id]) { _ in }
        try await scheduler.update(sessionID: second, ids: [id]) { _ in }
        #expect(await calls.count == 1)
        await scheduler.remove(sessionID: first)
        await scheduler.remove(sessionID: second)
        #expect(await scheduler.activeRefreshCount == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func staleProviderResultAfterUnsubscribeAndResubscribeIsNeverPublished() async throws {
        let id = RemoteControlID(kind: .builtIn, value: "2")
        let descriptor = Self.descriptor(id: id)
        let providerGate = TestGate()
        let firstStarted = TestSignal()
        let calls = IntegerProbe()
        let deliveries = RevisionProbe()
        let provider = RemoteCatalogProvider(
            catalog: { [descriptor] },
            status: { id, revision in
                let call = await calls.increment()
                if call == 1 {
                    await firstStarted.signal()
                    await providerGate.wait()
                }
                return Self.status(id: id, revision: revision)
            }
        )
        let scheduler = RemoteStatusScheduler(provider: provider, interval: .seconds(3_600), observeNotifications: false)
        let sessionID = UUID()
        let first = Task {
            try await scheduler.update(sessionID: sessionID, ids: [id]) { status in
                await deliveries.record(status.revision)
            }
        }
        await firstStarted.wait()
        await scheduler.remove(sessionID: sessionID)
        try await scheduler.update(sessionID: sessionID, ids: [id]) { status in
            await deliveries.record(status.revision)
        }

        await providerGate.open()
        await #expect(throws: CancellationError.self) { try await first.value }

        #expect(await deliveries.values == [2])
    }

    @Test(.timeLimit(.minutes(1)))
    func unsubscribeDuringDeliveryDoesNotEvictSession() async throws {
        let id = RemoteControlID(kind: .builtIn, value: "2")
        let descriptor = Self.descriptor(id: id)
        let deliveryStarted = TestSignal()
        let deliveryGate = TestGate()
        let evictions = IntegerProbe()
        let provider = RemoteCatalogProvider(
            catalog: { [descriptor] },
            status: { id, revision in Self.status(id: id, revision: revision) }
        )
        let scheduler = RemoteStatusScheduler(provider: provider, interval: .seconds(3_600), observeNotifications: false)
        let sessionID = UUID()
        let update = Task {
            try await scheduler.update(sessionID: sessionID, ids: [id], sink: { _ in
                await deliveryStarted.signal()
                await deliveryGate.wait()
                throw RevocationTestError.failed
            }, onFailure: {
                _ = await evictions.increment()
            })
        }
        await deliveryStarted.wait()
        await scheduler.remove(sessionID: sessionID)
        await deliveryGate.open()
        try await update.value

        #expect(await evictions.value == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func timeoutClosesStalledSinkWhileHealthyFanoutCompletes() async throws {
        let id = RemoteControlID(kind: .builtIn, value: "2")
        let descriptor = Self.descriptor(id: id)
        let stalledGate = TestGate()
        let stalledCalls = IntegerProbe()
        let healthyCalls = IntegerProbe()
        let evictions = IntegerProbe()
        let timeoutTrigger = TestGate()
        let completedDeadlines = TestSignal()
        let provider = RemoteCatalogProvider(
            catalog: { [descriptor] },
            status: { id, revision in Self.status(id: id, revision: revision) }
        )
        let scheduler = RemoteStatusScheduler(
            provider: provider,
            interval: .seconds(3_600),
            observeNotifications: false,
            deliveryDeadline: { _, onTimeout, operation in
                try await Self.runManualDeadline(
                    timeoutTrigger: timeoutTrigger,
                    onTimeout: onTimeout,
                    operation: operation
                )
                await completedDeadlines.signal()
            }
        )
        try await scheduler.update(sessionID: UUID(), ids: [id], sink: { _ in
            let call = await stalledCalls.increment()
            if call > 1 { await stalledGate.wait() }
        }, onFailure: {
            _ = await evictions.increment()
            await stalledGate.open()
        })
        try await scheduler.update(sessionID: UUID(), ids: [id]) { _ in
            _ = await healthyCalls.increment()
        }
        await completedDeadlines.wait()
        await completedDeadlines.wait()

        let refresh = Task { await scheduler.refreshAll() }
        await completedDeadlines.wait()
        await timeoutTrigger.open()
        await refresh.value

        #expect(await healthyCalls.value == 2)
        #expect(await evictions.value == 1)
    }

    private static func runManualDeadline(
        timeoutTrigger: TestGate,
        onTimeout: @escaping @Sendable () async -> Void,
        operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await operation()
                return false
            }
            group.addTask {
                await timeoutTrigger.wait()
                try Task.checkCancellation()
                await onTimeout()
                return true
            }
            guard let timedOut = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            if timedOut { throw RemoteStatusScheduler.DeliveryTimeout() }
        }
    }

    private static func descriptor(id: RemoteControlID) -> RemoteControlDescriptor {
        .init(
            id: id,
            title: "Dark Mode",
            behavior: .switch,
            icon: .systemSymbol("moon"),
            isAvailable: true,
            unavailableReason: nil,
            isDestructive: false,
            supportsStatus: true,
            supportsSecondaryInformation: false
        )
    }

    private static func status(id: RemoteControlID, revision: UInt64) -> RemoteControlStatus {
        .init(
            id: id,
            isAvailable: true,
            unavailableReason: nil,
            isOn: false,
            secondaryInformation: nil,
            isProcessing: false,
            revision: revision,
            updatedAt: .now
        )
    }
}

private actor StatusCallProbe {
    private(set) var ids: [RemoteControlID] = []
    var count: Int { ids.count }
    func record(_ id: RemoteControlID) { ids.append(id) }
}

private enum RevocationTestError: Error { case failed }
private enum StartTestError: Error { case listener, identity }

private actor StringEventProbe {
    private(set) var values: [String] = []
    func record(_ value: String) { values.append(value) }
}

private actor RevisionProbe {
    private(set) var values: [UInt64] = []
    func record(_ value: UInt64) { values.append(value) }
}

private actor IntegerProbe {
    private(set) var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
}

private actor TestGate {
    private var isOpen = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    func wait() async {
        guard isOpen == false else { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiters[id] = $0 }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    func open() {
        isOpen = true
        let current = waiters.values
        waiters.removeAll()
        current.forEach { $0.resume() }
    }

    private func cancelWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume()
    }
}

private actor TestSignal {
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            count += 1
        }
    }

    func wait() async {
        if count > 0 {
            count -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor PairingLifecycleHarness {
    private var lifecycle = RemoteHostLifecycle()
    private let generation: UInt64

    init() {
        generation = lifecycle.beginStart()
        _ = lifecycle.markListening(generation: generation)
    }

    func epoch(for deviceID: UUID) -> UInt64 { lifecycle.pairingEpoch(for: deviceID) }
    func revoke(_ deviceID: UUID) { _ = lifecycle.revoke(deviceID: deviceID) }
    func stop() { _ = lifecycle.stop() }
    func snapshot(for deviceID: UUID) -> RemotePairingSnapshot? {
        lifecycle.pairingSnapshot(for: deviceID, generation: generation)
    }
    func validate(_ snapshot: RemotePairingSnapshot) -> Bool {
        lifecycle.validateRepair(snapshot)
    }
    func commit(_ snapshot: RemotePairingSnapshot) -> Bool {
        lifecycle.commitRepair(snapshot)
    }
    func rollback(_ snapshot: RemotePairingSnapshot) -> Bool {
        lifecycle.rollbackRepair(snapshot)
    }
    func isRevoked(_ deviceID: UUID) -> Bool {
        lifecycle.isRevoked(deviceID)
    }
    func canAuthenticate(_ deviceID: UUID) -> Bool {
        let sessionID = UUID()
        guard lifecycle.acceptPending(sessionID: sessionID, generation: generation) else { return false }
        return lifecycle.authorize(
            sessionID: sessionID,
            deviceID: deviceID,
            generation: generation,
            credentialExists: true
        )
    }
}
