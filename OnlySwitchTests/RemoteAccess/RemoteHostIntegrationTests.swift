import Foundation
import RemoteCore
import RemoteTransport
import Testing
import Switches
@testable import OnlySwitch

struct RemoteHostIntegrationTests {
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
        #expect(try await ordinaryClient.authenticate(credential: identity.credential) == .authenticated)
        #expect(boundary.events == [.sendInvoked, .sendReturned])

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
    func repairAuthenticationResultSendFailureRollsBackCredentialRevocationAndVerifier() async throws {
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
        boundary.failNextSend()
        let repairClient = try await RemoteHostTestClient.connect(to: endpoint, deviceID: original.deviceID)

        do {
            try await repairClient.pair(code: "ABCDEFGH2345")
            Issue.record("Expected the authentication result send to fail")
        } catch {}

        #expect(try await host.pairedDevices().first?.credential == original.credential)
        #expect(await host.isRevokedForTesting(deviceID: original.deviceID))
        #expect(try await host.revocationVerifierForTesting(deviceID: original.deviceID) == RemoteHandshakeCrypto.revocationVerifier(credential: original.credential))
        #expect(boundary.events == [.sendInvoked])

        try await host.deleteCredentialForTesting(
            deviceID: original.deviceID,
            matching: original.credential
        )
        let offlineClient = try await RemoteHostTestClient.connect(to: endpoint, deviceID: original.deviceID)
        #expect(try await offlineClient.authenticate(credential: original.credential) == .revoked)
    }

    @Test(.timeLimit(.minutes(1)))
    func successfulRepairClearsVerifierOnlyAfterAuthenticationResultSend() async throws {
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
