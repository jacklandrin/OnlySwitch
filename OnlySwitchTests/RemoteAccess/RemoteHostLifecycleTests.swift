import Foundation
import RemoteCore
import Testing
@testable import OnlySwitch

struct RemoteHostLifecycleTests {
    @Test
    func revokeWhileAuthenticationIsSuspendedCannotRegisterSession() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 2, maximumAuthenticatedSessions: 2)
        let generation = lifecycle.beginStart()
        #expect(lifecycle.markListening(generation: generation))
        let sessionID = UUID()
        let deviceID = UUID()
        #expect(lifecycle.acceptPending(sessionID: sessionID, generation: generation))

        #expect(lifecycle.revoke(deviceID: deviceID).isEmpty)
        #expect(lifecycle.authorize(
            sessionID: sessionID,
            deviceID: deviceID,
            generation: generation,
            credentialExists: true
        ) == false)
        #expect(lifecycle.authenticatedCount == 0)
    }

    @Test
    func stopWhileAuthenticationIsSuspendedInvalidatesGenerationAndClearsState() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 2, maximumAuthenticatedSessions: 2)
        let generation = lifecycle.beginStart()
        #expect(lifecycle.markListening(generation: generation))
        let sessionID = UUID()
        #expect(lifecycle.acceptPending(sessionID: sessionID, generation: generation))

        let sessionsToClose = lifecycle.stop()

        #expect(sessionsToClose == [sessionID])
        #expect(lifecycle.authorize(
            sessionID: sessionID,
            deviceID: UUID(),
            generation: generation,
            credentialExists: true
        ) == false)
        #expect(lifecycle.pendingCount == 0)
        #expect(lifecycle.authenticatedCount == 0)
    }

    @Test
    func pendingAndAuthenticatedCapsAreEnforcedIndependently() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 1, maximumAuthenticatedSessions: 1)
        let generation = lifecycle.beginStart()
        #expect(lifecycle.markListening(generation: generation))
        let first = UUID()
        let second = UUID()
        #expect(lifecycle.acceptPending(sessionID: first, generation: generation))
        #expect(lifecycle.acceptPending(sessionID: second, generation: generation) == false)
        #expect(lifecycle.authorize(
            sessionID: first,
            deviceID: UUID(),
            generation: generation,
            credentialExists: true
        ))
        #expect(lifecycle.acceptPending(sessionID: second, generation: generation))
        #expect(lifecycle.authorize(
            sessionID: second,
            deviceID: UUID(),
            generation: generation,
            credentialExists: true
        ) == false)
    }

    @Test
    func staleListenerCallbacksCannotChangeNewLifecycle() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 1, maximumAuthenticatedSessions: 1)
        let staleGeneration = lifecycle.beginStart()
        _ = lifecycle.stop()
        let currentGeneration = lifecycle.beginStart()

        #expect(lifecycle.markListening(generation: staleGeneration) == false)
        #expect(lifecycle.markListening(generation: currentGeneration))
        #expect(lifecycle.fail(generation: staleGeneration).isEmpty)
        #expect(lifecycle.isListening(generation: currentGeneration))
    }

    @Test
    func listenerFailureTearsDownCurrentGenerationExactlyOnce() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 2, maximumAuthenticatedSessions: 2)
        let generation = lifecycle.beginStart()
        #expect(lifecycle.markListening(generation: generation))
        let sessionID = UUID()
        #expect(lifecycle.acceptPending(sessionID: sessionID, generation: generation))

        #expect(lifecycle.fail(generation: generation) == [sessionID])
        #expect(lifecycle.fail(generation: generation).isEmpty)
        #expect(lifecycle.isActive(generation: generation) == false)
    }

    @Test
    func endingAStaleSessionAlwaysRemovesPendingAndAuthenticatedMappings() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 2, maximumAuthenticatedSessions: 2)
        let generation = lifecycle.beginStart()
        #expect(lifecycle.markListening(generation: generation))
        let sessionID = UUID()
        #expect(lifecycle.acceptPending(sessionID: sessionID, generation: generation))
        #expect(lifecycle.authorize(
            sessionID: sessionID,
            deviceID: UUID(),
            generation: generation,
            credentialExists: true
        ))

        #expect(lifecycle.end(sessionID: sessionID))
        #expect(lifecycle.end(sessionID: sessionID) == false)
        #expect(lifecycle.pendingCount == 0)
        #expect(lifecycle.authenticatedCount == 0)
    }

    @Test
    func revocationAfterPairingAuthorizationPreventsTombstoneClear() {
        var lifecycle = RemoteHostLifecycle(maximumPendingHandshakes: 1, maximumAuthenticatedSessions: 1)
        let generation = lifecycle.beginStart()
        #expect(lifecycle.markListening(generation: generation))
        let deviceID = UUID()
        let pairingEpoch = lifecycle.pairingEpoch(for: deviceID)

        _ = lifecycle.revoke(deviceID: deviceID)

        #expect(lifecycle.allowRepairedDevice(
            deviceID,
            pairingEpoch: pairingEpoch,
            generation: generation
        ) == false)
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

    @Test
    func stalledSinkTimesOutWithoutBlockingHealthySinkAndIsEvicted() async throws {
        let id = RemoteControlID(kind: .builtIn, value: "2")
        let descriptor = Self.descriptor(id: id)
        let provider = RemoteCatalogProvider(
            catalog: { [descriptor] },
            status: { id, revision in Self.status(id: id, revision: revision) }
        )
        let scheduler = RemoteStatusScheduler(
            provider: provider,
            interval: .seconds(3_600),
            observeNotifications: false,
            sendTimeout: .milliseconds(50)
        )
        let evictions = StatusCallProbe()
        let deliveries = StatusCallProbe()

        try await scheduler.update(sessionID: UUID(), ids: [id], sink: { _ in
            try await Task.sleep(for: .seconds(3_600))
        }, onFailure: {
            await evictions.record(id)
        })
        try await scheduler.update(sessionID: UUID(), ids: [id], sink: { _ in
            await deliveries.record(id)
        })

        #expect(await evictions.count == 1)
        #expect(await deliveries.count == 1)
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
