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
    func stoppedRepairRestoresExistingCredential() async throws {
        let store = RemoteCredentialStore.inMemory()
        let deviceID = UUID()
        let original = Self.device(id: deviceID, byte: 1)
        let replacement = Self.device(id: deviceID, byte: 2)
        let lifecycle = PairingLifecycleHarness()
        try await store.save(original)

        let transaction = try await RemotePairingTransaction.begin(
            record: replacement,
            credentialStore: store,
            pairingEpoch: { await lifecycle.epoch(for: $0) },
            consumePairing: { true }
        )
        await lifecycle.stop()
        #expect(await transaction.authorize { id, epoch in
            await lifecycle.authorizeRepair(id: id, epoch: epoch)
        } == false)
        await transaction.rollback(
            credentialStore: store,
            pairingEpoch: { await lifecycle.epoch(for: $0) }
        )

        #expect(try await store.load(deviceID) == original)
    }

    @Test
    func revokedRepairNeverRestoresExistingCredential() async throws {
        let store = RemoteCredentialStore.inMemory()
        let deviceID = UUID()
        let original = Self.device(id: deviceID, byte: 1)
        let replacement = Self.device(id: deviceID, byte: 2)
        let lifecycle = PairingLifecycleHarness()
        try await store.save(original)

        let transaction = try await RemotePairingTransaction.begin(
            record: replacement,
            credentialStore: store,
            pairingEpoch: { await lifecycle.epoch(for: $0) },
            consumePairing: {
                await lifecycle.revoke(deviceID)
                return true
            }
        )
        #expect(await transaction.authorize { id, epoch in
            await lifecycle.authorizeRepair(id: id, epoch: epoch)
        } == false)
        await transaction.rollback(
            credentialStore: store,
            pairingEpoch: { await lifecycle.epoch(for: $0) }
        )

        #expect(try await store.load(deviceID) == nil)
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
    func authorizeRepair(id: UUID, epoch: UInt64) -> Bool {
        lifecycle.allowRepairedDevice(id, pairingEpoch: epoch, generation: generation)
    }
}
