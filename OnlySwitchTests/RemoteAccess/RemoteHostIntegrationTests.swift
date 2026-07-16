import Foundation
import RemoteCore
import RemoteTransport
import Testing
import Switches
@testable import OnlySwitch

struct RemoteHostIntegrationTests {
    @Test
    func preparedReplacementDoesNotReplaceCommittedCredential() async throws {
        let store = RemoteCredentialStore.inMemory()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000920")!
        let old = PairedRemoteDevice(
            id: id,
            name: "Phone",
            credential: Data(repeating: 1, count: 32),
            createdAt: .distantPast,
            lastConnectedAt: nil
        )
        let candidate = PairedRemoteDevice(
            id: id,
            name: "Phone",
            credential: Data(repeating: 2, count: 32),
            createdAt: .now,
            lastConnectedAt: nil
        )
        try await store.save(old)
        let transactionID = UUID()

        try await store.prepareReplacement(
            candidate,
            transactionID: transactionID,
            expiresAt: .distantFuture
        )

        #expect(try await store.load(old.id) == old)
        #expect(try await store.transactionStatus(transactionID) == .prepared)
        _ = try await store.finalizePrepared(transactionID)
        #expect(try await store.load(old.id)?.credential == candidate.credential)
        #expect(try await store.transactionStatus(transactionID) == .committed)
    }

    @Test
    func abortAndExpiryRestorePreviousCredentialIdempotently() async throws {
        let store = RemoteCredentialStore.inMemory()
        let existingID = UUID(uuidString: "00000000-0000-0000-0000-000000000921")!
        let old = PairedRemoteDevice(
            id: existingID,
            name: "Phone",
            credential: Data(repeating: 1, count: 32),
            createdAt: .distantPast,
            lastConnectedAt: nil
        )
        let replacement = PairedRemoteDevice(
            id: existingID,
            name: "Phone",
            credential: Data(repeating: 2, count: 32),
            createdAt: .now,
            lastConnectedAt: nil
        )
        try await store.save(old)
        let replacementID = UUID()
        try await store.prepareReplacement(
            replacement,
            transactionID: replacementID,
            expiresAt: .distantFuture
        )
        try await store.abortPrepared(replacementID)
        try await store.abortPrepared(replacementID)
        #expect(try await store.load(existingID) == old)
        #expect(try await store.transactionRetainsPreviousCredentialForTesting(replacementID) == false)
        let restartedAfterAbort = await store.restartedInMemoryForTesting()
        #expect(try await restartedAfterAbort.transactionRetainsPreviousCredentialForTesting(replacementID) == false)

        let newID = UUID(uuidString: "00000000-0000-0000-0000-000000000922")!
        let newDevice = PairedRemoteDevice(
            id: newID,
            name: "Tablet",
            credential: Data(repeating: 3, count: 32),
            createdAt: .now,
            lastConnectedAt: nil
        )
        let expiringID = UUID()
        try await store.prepareReplacement(
            newDevice,
            transactionID: expiringID,
            expiresAt: Date(timeIntervalSince1970: 10)
        )
        try await store.recoverExpiredTransactions(now: Date(timeIntervalSince1970: 11))
        #expect(try await store.load(newID) == nil)
        #expect(try await store.transactionStatus(expiringID) == .aborted)
        #expect(try await store.transactionRetainsPreviousCredentialForTesting(expiringID) == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func prepareDoesNotReplaceCommittedCredential() async throws {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let host = RemoteHost.testing(catalog: [], router: router, pairingCode: "ABCDEFGH2345")
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let originalClient = try await RemoteHostTestClient.connect(to: endpoint)
        try await originalClient.pair(code: "ABCDEFGH2345")
        let original = try #require(try await host.pairedDevices().first)
        _ = await host.startPairing()
        let repairClient = try await RemoteHostTestClient.connect(to: endpoint, deviceID: original.id)

        let prepared = try await repairClient.preparePairing(code: "ABCDEFGH2345")

        #expect(try await host.pairedDevices().first == original)
        try await repairClient.sendTransaction(.pairingAbort(.init(transactionID: prepared.transactionID)))
        #expect(try await repairClient.receiveTransactionStatus().state == .aborted)
    }

    @Test(.timeLimit(.minutes(1)))
    func provisionalPeerRejectsAction() async throws {
        let control = await MainActor.run { FakeSwitch(type: .darkMode, visible: true) }
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in control }) }
        let host = RemoteHost.testing(catalog: [], router: router, pairingCode: "ABCDEFGH2345")
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let client = try await RemoteHostTestClient.connect(to: endpoint)
        _ = try await client.preparePairing(code: "ABCDEFGH2345")
        let request = RemoteActionRequest(
            requestID: UUID(),
            controlID: .init(kind: .builtIn, value: String(SwitchType.darkMode.rawValue)),
            action: .setState(true)
        )

        await #expect(throws: (any Error).self) {
            _ = try await client.send(request)
        }
        #expect(await MainActor.run { control.operationCount } == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func abortRestoresPreviousCredential() async throws {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let host = RemoteHost.testing(catalog: [], router: router, pairingCode: "ABCDEFGH2345")
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let oldClient = try await RemoteHostTestClient.connect(to: endpoint)
        try await oldClient.pair(code: "ABCDEFGH2345")
        let original = try #require(try await host.pairedDevices().first)
        _ = await host.startPairing()
        let repairClient = try await RemoteHostTestClient.connect(to: endpoint, deviceID: original.id)
        let prepared = try await repairClient.preparePairing(code: "ABCDEFGH2345")

        try await repairClient.sendTransaction(.pairingAbort(.init(transactionID: prepared.transactionID)))
        #expect(try await repairClient.receiveTransactionStatus().state == .aborted)
        #expect(try await host.pairedDevices().first == original)
    }

    @Test(.timeLimit(.minutes(1)))
    func commitIsIdempotent() async throws {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let host = RemoteHost.testing(catalog: [], router: router, pairingCode: "ABCDEFGH2345")
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let client = try await RemoteHostTestClient.connect(to: endpoint)
        let prepared = try await client.preparePairing(code: "ABCDEFGH2345")
        let command = RemoteMessage.pairingCommit(.init(transactionID: prepared.transactionID))

        try await client.sendTransaction(command)
        #expect(try await client.receiveTransactionStatus().state == .committed)
        try await client.sendTransaction(command)
        #expect(try await client.receiveTransactionStatus().state == .committed)
        #expect(try await host.pairedDevices().first?.credential == prepared.credential)
    }

    @Test(.timeLimit(.minutes(1)))
    func lostCommitConfirmationResolvesThroughStatus() async throws {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let boundary = AuthenticationResultBoundaryRecorder()
        let host = RemoteHost.testing(
            catalog: [],
            router: router,
            pairingCode: "ABCDEFGH2345",
            authenticationResultSender: { try await boundary.send($0) }
        )
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let client = try await RemoteHostTestClient.connect(to: endpoint)
        let prepared = try await client.preparePairing(code: "ABCDEFGH2345")
        boundary.failNextSend()
        try await client.sendTransaction(.pairingCommit(.init(transactionID: prepared.transactionID)))
        await #expect(throws: (any Error).self) {
            _ = try await client.receiveTransactionStatus()
        }

        let recovery = try await RemoteHostTestClient.connect(to: endpoint, deviceID: await client.id)
        #expect(try await recovery.authenticate(credential: prepared.credential) == .authenticated)
        try await recovery.sendTransaction(.pairingStatusRequest(.init(transactionID: prepared.transactionID)))
        #expect(try await recovery.receiveTransactionStatus().state == .committed)
    }

    @Test
    func expiryRecoveryAbortsPreparedRecord() async throws {
        let store = RemoteCredentialStore.inMemory()
        let device = PairedRemoteDevice(
            id: UUID(),
            name: "Phone",
            credential: Data(repeating: 4, count: 32),
            createdAt: .now,
            lastConnectedAt: nil
        )
        let transactionID = UUID()
        try await store.prepareReplacement(
            device,
            transactionID: transactionID,
            expiresAt: Date(timeIntervalSince1970: 20)
        )

        try await store.recoverExpiredTransactions(now: Date(timeIntervalSince1970: 21))

        #expect(try await store.transactionStatus(transactionID) == .aborted)
        #expect(try await store.load(device.id) == nil)
    }

    @Test
    func mismatchedTransactionCandidateIsRejectedWithoutMutation() async throws {
        let store = RemoteCredentialStore.inMemory()
        let transactionID = UUID()
        let original = PairedRemoteDevice(
            id: UUID(),
            name: "Phone",
            credential: Data(repeating: 5, count: 32),
            createdAt: .now,
            lastConnectedAt: nil
        )
        var mismatch = original
        mismatch.name = "Different Phone"
        try await store.prepareReplacement(
            original,
            transactionID: transactionID,
            expiresAt: .distantFuture
        )

        await #expect(throws: RemoteProtocolError.self) {
            try await store.prepareReplacement(
                mismatch,
                transactionID: transactionID,
                expiresAt: .distantFuture
            )
        }

        #expect(try await store.transactionStatus(transactionID) == .prepared)
        #expect(try await store.load(original.id) == nil)
    }

    @Test
    func preparedTransactionCountIsBounded() async throws {
        let store = RemoteCredentialStore.inMemory()
        for byte in UInt8(0)..<UInt8(32) {
            try await store.prepareReplacement(
                .init(
                    id: UUID(),
                    name: "Phone",
                    credential: Data(repeating: byte, count: 32),
                    createdAt: .now,
                    lastConnectedAt: nil
                ),
                transactionID: UUID(),
                expiresAt: .distantFuture
            )
        }
        let overflow = PairedRemoteDevice(
            id: UUID(),
            name: "Overflow",
            credential: Data(repeating: 32, count: 32),
            createdAt: .now,
            lastConnectedAt: nil
        )

        await #expect(throws: RemoteProtocolError.self) {
            try await store.prepareReplacement(
                overflow,
                transactionID: UUID(),
                expiresAt: .distantFuture
            )
        }
        #expect(try await store.load(overflow.id) == nil)
    }

    @Test
    func revocationSerializesAgainstPreparedFinalization() async throws {
        let deviceID = UUID()
        let old = PairedRemoteDevice(
            id: deviceID,
            name: "Phone",
            credential: Data(repeating: 6, count: 32),
            createdAt: .distantPast,
            lastConnectedAt: nil
        )
        let candidate = PairedRemoteDevice(
            id: deviceID,
            name: "Phone",
            credential: Data(repeating: 7, count: 32),
            createdAt: .now,
            lastConnectedAt: nil
        )

        let revokeFirst = RemoteCredentialStore.inMemory()
        try await revokeFirst.save(old)
        let abortedID = UUID()
        try await revokeFirst.prepareReplacement(candidate, transactionID: abortedID, expiresAt: .distantFuture)
        #expect(try await revokeFirst.prepareAndDeleteForRevocation(deviceID) == old.credential)
        await #expect(throws: RemoteProtocolError.self) {
            _ = try await revokeFirst.finalizePrepared(abortedID)
        }
        #expect(try await revokeFirst.load(deviceID) == nil)

        let commitFirst = RemoteCredentialStore.inMemory()
        try await commitFirst.save(old)
        let committedID = UUID()
        try await commitFirst.prepareReplacement(candidate, transactionID: committedID, expiresAt: .distantFuture)
        _ = try await commitFirst.finalizePrepared(committedID)
        #expect(try await commitFirst.prepareAndDeleteForRevocation(deviceID) == candidate.credential)
        #expect(try await commitFirst.load(deviceID) == nil)
        #expect(try await commitFirst.loadRevocationVerifier(deviceID) == RemoteHandshakeCrypto.revocationVerifier(credential: candidate.credential))
    }

    @Test
    func verifierWrittenBeforeDeleteRejectsMatchingCredentialAfterRecovery() async throws {
        let deviceID = UUID()
        let revoked = PairedRemoteDevice(
            id: deviceID,
            name: "Phone",
            credential: Data(repeating: 8, count: 32),
            createdAt: .distantPast,
            lastConnectedAt: nil
        )
        let repaired = PairedRemoteDevice(
            id: deviceID,
            name: "Phone",
            credential: Data(repeating: 9, count: 32),
            createdAt: .now,
            lastConnectedAt: nil
        )
        let store = RemoteCredentialStore.inMemory(
            beforeRevocationDelete: { throw RevocationBoundaryFailure.injected }
        )
        try await store.save(revoked)

        await #expect(throws: RevocationBoundaryFailure.self) {
            _ = try await store.prepareAndDeleteForRevocation(deviceID)
        }

        let restarted = await store.restartedInMemoryForTesting()
        #expect(try await restarted.authenticationRecord(deviceID) == .revoked)
        try await restarted.save(repaired)
        #expect(try await restarted.authenticationRecord(deviceID) == .credential(repaired))
    }

    @Test(.timeLimit(.minutes(1)))
    func closeAfterDurableFinalizeDoesNotAuthenticateClosedPeer() async throws {
        try await assertCommitCloseRecovery(at: .afterFinalize)
    }

    @Test(.timeLimit(.minutes(1)))
    func closeBeforeHostAuthenticationDoesNotLeakAuthenticatedSession() async throws {
        try await assertCommitCloseRecovery(at: .beforeHostAuthentication)
    }

    @Test(.timeLimit(.minutes(1)))
    func minorOneClientCannotStartTransactionalPairing() async throws {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let host = RemoteHost.testing(catalog: [], router: router, pairingCode: "ABCDEFGH2345")
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let client = try await RemoteHostTestClient.connect(
            to: endpoint,
            version: .init(major: 1, minor: 1)
        )

        await #expect(throws: (any Error).self) {
            _ = try await client.preparePairing(code: "ABCDEFGH2345")
        }
        #expect(try await host.pairedDevices().isEmpty)
    }

    private func assertCommitCloseRecovery(at stage: RemotePairingCommitStage) async throws {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let gate = RemoteHostTestGate()
        let authenticationInvocations = AuthenticationInvocationRecorder()
        let host = RemoteHost.testing(
            catalog: [],
            router: router,
            pairingCode: "ABCDEFGH2345",
            commitStageReached: { reached in
                if reached == stage { await gate.wait() }
            },
            authenticatedSessionObserver: { authenticationInvocations.record() }
        )
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let client = try await RemoteHostTestClient.connect(to: endpoint)
        let prepared = try await client.preparePairing(code: "ABCDEFGH2345")
        try await client.sendTransaction(.pairingCommit(.init(transactionID: prepared.transactionID)))
        await gate.waitUntilEntered()

        await host.closeSessionsForTesting()
        await gate.open()
        await #expect(throws: (any Error).self) {
            _ = try await client.receiveTransactionStatus()
        }
        #expect(await host.authenticatedSessionCountForTesting() == 0)
        #expect(authenticationInvocations.count == 0)

        let recovery = try await RemoteHostTestClient.connect(to: endpoint, deviceID: await client.id)
        #expect(try await recovery.authenticate(credential: prepared.credential) == .authenticated)
        try await recovery.sendTransaction(.pairingStatusRequest(.init(transactionID: prepared.transactionID)))
        #expect(try await recovery.receiveTransactionStatus().state == .committed)
    }

    @Test(.timeLimit(.minutes(1)))
    func pairsAuthenticatesAndDeduplicatesAnActionOverLoopback() async throws {
        let control = await MainActor.run { FakeSwitch(type: .darkMode, visible: true) }
        let router = await MainActor.run {
            RemoteCommandRouter(resolveBuiltIn: { _ in control })
        }
        let descriptor = RemoteControlDescriptor(
            id: .init(kind: .builtIn, value: String(SwitchType.darkMode.rawValue)),
            title: "Dark Mode",
            behavior: .switch,
            icon: .systemSymbol("moon"),
            isAvailable: true,
            unavailableReason: nil,
            isDestructive: false,
            supportsStatus: true,
            supportsSecondaryInformation: false
        )
        let host = RemoteHost.testing(
            catalog: [descriptor],
            router: router,
            pairingCode: "ABCDEFGH2345"
        )
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let client = try await RemoteHostTestClient.connect(to: endpoint)

        try await client.pair(code: "ABCDEFGH2345")
        #expect(try await client.catalog().contains { $0.title == "Dark Mode" })
        try await client.subscribe([descriptor.id])
        #expect(try await client.nextStatus(for: descriptor.id).id == descriptor.id)

        let request = RemoteActionRequest(
            requestID: UUID(),
            controlID: descriptor.id,
            action: .setState(true)
        )
        let first = try await client.send(request)
        let second = try await client.send(request)

        #expect(first == second)
        #expect(await MainActor.run { control.operationCount } == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func catalogChangesBroadcastOnlyAfterStructuralChangeAndRefreshUsesSameRevision() async throws {
        let id = RemoteControlID(kind: .shortcut, value: "Morning")
        let initial = RemoteControlDescriptor(
            id: id,
            title: "Morning",
            behavior: .button,
            icon: .systemSymbol("sunrise"),
            isAvailable: true,
            unavailableReason: nil,
            isDestructive: false,
            supportsStatus: false,
            supportsSecondaryInformation: false
        )
        let changed = RemoteControlDescriptor(
            id: id,
            title: "Morning",
            behavior: .button,
            icon: .systemSymbol("sunrise"),
            isAvailable: false,
            unavailableReason: "Shortcut is unavailable",
            isDestructive: false,
            supportsStatus: false,
            supportsSecondaryInformation: false
        )
        let source = IntegrationCatalogSource([initial])
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let host = RemoteHost.testing(
            catalog: [],
            catalogProvider: await source.provider,
            router: router,
            pairingCode: "ABCDEFGH2345"
        )
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let client = try await RemoteHostTestClient.connect(to: endpoint)
        try await client.pair(code: "ABCDEFGH2345")
        #expect(await client.authenticatedCatalogRevision == 1)
        #expect(try await client.catalogSnapshot() == .init(revision: 1, controls: [initial]))
        _ = await host.startPairing()
        let secondClient = try await RemoteHostTestClient.connect(to: endpoint)
        try await secondClient.pair(code: "ABCDEFGH2345")
        #expect(await secondClient.authenticatedCatalogRevision == 1)
        #expect(try await secondClient.catalogSnapshot() == .init(revision: 1, controls: [initial]))

        #expect(try await host.refreshCatalogForTesting() == nil)
        await source.set([changed])
        let snapshot = try #require(try await host.refreshCatalogForTesting())
        #expect(snapshot.revision == 2)
        #expect(try await client.nextMessage() == .catalogChanged(revision: 2))
        #expect(try await secondClient.nextMessage() == .catalogChanged(revision: 2))
        #expect(try await client.catalogSnapshot() == .init(revision: 2, controls: [changed]))
        #expect(try await secondClient.catalogSnapshot() == .init(revision: 2, controls: [changed]))
    }

    @Test(.timeLimit(.minutes(1)))
    func wrongPairingProofIsRejected() async throws {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let host = RemoteHost.testing(catalog: [], router: router, pairingCode: "ABCDEFGH2345")
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let client = try await RemoteHostTestClient.connect(to: endpoint)

        await #expect(throws: RemoteProtocolError.self) {
            try await client.pair(code: "ZZZZZZZZZZZZ")
        }
        #expect(try await host.pairedDevices().isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func liveRevocationIsAuthenticatedBeforeSessionCloses() async throws {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let host = RemoteHost.testing(catalog: [], router: router, pairingCode: "ABCDEFGH2345")
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let client = try await RemoteHostTestClient.connect(to: endpoint)
        try await client.pair(code: "ABCDEFGH2345")
        let device = try #require(try await host.pairedDevices().first)

        try await host.revoke(deviceID: device.id)

        #expect(try await client.nextMessage() == .credentialRevoked)
        #expect(try await host.pairedDevices().isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func ordinaryAuthenticationDuringRevocationCannotClearOfflineVerifier() async throws {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let gate = RemoteHostTestGate()
        let boundary = AuthenticationResultBoundaryRecorder()
        let host = RemoteHost.testing(
            catalog: [],
            router: router,
            pairingCode: "ABCDEFGH2345",
            revocationPrepared: { await gate.wait() },
            authenticationResultSender: { try await boundary.send($0) },
            finalizeRepairObserver: { _ in boundary.recordFinalized() }
        )
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let pairedClient = try await RemoteHostTestClient.connect(to: endpoint)
        try await pairedClient.pair(code: "ABCDEFGH2345")
        let identity = try await pairedClient.pairingIdentity()
        boundary.reset()

        let revocation = Task { try await host.revoke(deviceID: identity.deviceID) }
        await gate.waitUntilEntered()
        let ordinaryClient = try await RemoteHostTestClient.connect(
            to: endpoint,
            deviceID: identity.deviceID
        )
        #expect(try await ordinaryClient.authenticate(credential: identity.credential) == .revoked)
        #expect(boundary.events.isEmpty)

        await gate.open()
        try await revocation.value
        #expect(try await host.pairedDevices().isEmpty)

        let offlineClient = try await RemoteHostTestClient.connect(
            to: endpoint,
            deviceID: identity.deviceID
        )
        #expect(try await offlineClient.authenticate(credential: identity.credential) == .revoked)
    }

    @Test(.timeLimit(.minutes(1)))
    func repairCommitConfirmationFailureRetainsCommittedCredentialAndVerifier() async throws {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let boundary = AuthenticationResultBoundaryRecorder()
        let host = RemoteHost.testing(
            catalog: [],
            router: router,
            pairingCode: "ABCDEFGH2345",
            authenticationResultSender: { try await boundary.send($0) },
            finalizeRepairObserver: { _ in boundary.recordFinalized() }
        )
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let originalClient = try await RemoteHostTestClient.connect(to: endpoint)
        try await originalClient.pair(code: "ABCDEFGH2345")
        let original = try await originalClient.pairingIdentity()
        try await host.revokePreservingCredentialForTesting(deviceID: original.deviceID)
        _ = await host.startPairing()
        boundary.reset()
        let repairClient = try await RemoteHostTestClient.connect(to: endpoint, deviceID: original.deviceID)
        let prepared = try await repairClient.preparePairing(code: "ABCDEFGH2345")
        boundary.failNextSend()
        try await repairClient.sendTransaction(.pairingCommit(.init(transactionID: prepared.transactionID)))

        await #expect(throws: (any Error).self) {
            _ = try await repairClient.receiveTransactionStatus()
        }

        let committed = try #require(try await host.pairedDevices().first)
        #expect(committed.credential != original.credential)
        #expect(await host.isRevokedForTesting(deviceID: original.deviceID) == false)
        #expect(try await host.revocationVerifierForTesting(deviceID: original.deviceID) == RemoteHandshakeCrypto.revocationVerifier(credential: original.credential))
        #expect(boundary.events == [.sendInvoked])

        let recovery = try await RemoteHostTestClient.connect(to: endpoint, deviceID: original.deviceID)
        #expect(try await recovery.authenticate(credential: committed.credential) == .authenticated)
        try await recovery.sendTransaction(.pairingCommit(.init(transactionID: prepared.transactionID)))
        #expect(try await recovery.receiveTransactionStatus().state == .committed)
        #expect(try await host.revocationVerifierForTesting(deviceID: original.deviceID) == nil)
        try await recovery.sendTransaction(.pairingStatusRequest(.init(transactionID: prepared.transactionID)))
        #expect(try await recovery.receiveTransactionStatus().state == .committed)
    }

    @Test(.timeLimit(.minutes(1)))
    func successfulRepairClearsVerifierOnlyAfterCommitConfirmation() async throws {
        let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in nil }) }
        let boundary = AuthenticationResultBoundaryRecorder()
        let host = RemoteHost.testing(
            catalog: [],
            router: router,
            pairingCode: "ABCDEFGH2345",
            authenticationResultSender: { try await boundary.send($0) },
            finalizeRepairObserver: { _ in boundary.recordFinalized() }
        )
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let originalClient = try await RemoteHostTestClient.connect(to: endpoint)
        try await originalClient.pair(code: "ABCDEFGH2345")
        let original = try await originalClient.pairingIdentity()
        try await host.revokePreservingCredentialForTesting(deviceID: original.deviceID)
        _ = await host.startPairing()
        boundary.reset()
        let repairClient = try await RemoteHostTestClient.connect(to: endpoint, deviceID: original.deviceID)

        try await repairClient.pair(code: "ABCDEFGH2345")
        await boundary.waitUntilFinalized()

        let repaired = try #require(try await host.pairedDevices().first)
        #expect(repaired.credential != original.credential)
        #expect(await host.isRevokedForTesting(deviceID: original.deviceID) == false)
        #expect(try await host.revocationVerifierForTesting(deviceID: original.deviceID) == nil)
        #expect(boundary.events == [.sendInvoked, .sendReturned, .finalized])
    }

}

private actor IntegrationCatalogSource {
    private var controls: [RemoteControlDescriptor]

    init(_ controls: [RemoteControlDescriptor]) { self.controls = controls }

    var provider: RemoteCatalogProvider {
        RemoteCatalogProvider(
            catalog: { [weak self] in await self?.controls ?? [] },
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

    func set(_ controls: [RemoteControlDescriptor]) { self.controls = controls }
}

private enum AuthenticationResultSendFailure: Swift.Error { case injected }
private enum RevocationBoundaryFailure: Swift.Error { case injected }

private enum AuthenticationBoundaryEvent: Equatable {
    case sendInvoked
    case sendReturned
    case finalized
}

private final class AuthenticationResultBoundaryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [AuthenticationBoundaryEvent] = []
    private var shouldFail = false
    private var finalizeWaiters: [CheckedContinuation<Void, Never>] = []

    var events: [AuthenticationBoundaryEvent] { lock.withLock { recordedEvents } }

    func reset() {
        lock.withLock {
            recordedEvents = []
            shouldFail = false
        }
    }

    func failNextSend() { lock.withLock { shouldFail = true } }

    func send(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        let fails = lock.withLock { () -> Bool in
            recordedEvents.append(.sendInvoked)
            defer { shouldFail = false }
            return shouldFail
        }
        if fails { throw AuthenticationResultSendFailure.injected }
        try await operation()
        lock.withLock { recordedEvents.append(.sendReturned) }
    }

    func recordFinalized() {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            recordedEvents.append(.finalized)
            defer { finalizeWaiters = [] }
            return finalizeWaiters
        }
        for waiter in waiters { waiter.resume() }
    }

    func waitUntilFinalized() async {
        if lock.withLock({ recordedEvents.contains(.finalized) }) { return }
        await withCheckedContinuation { continuation in
            let alreadyFinalized = lock.withLock { () -> Bool in
                guard recordedEvents.contains(.finalized) == false else { return true }
                finalizeWaiters.append(continuation)
                return false
            }
            if alreadyFinalized { continuation.resume() }
        }
    }
}

private final class AuthenticationInvocationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var invocations = 0

    var count: Int { lock.withLock { invocations } }

    func record() { lock.withLock { invocations += 1 } }
}

private actor RemoteHostTestGate {
    private var isOpen = false
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var enteredWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        guard isOpen == false else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func waitUntilEntered() async {
        guard entered == false else { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}
