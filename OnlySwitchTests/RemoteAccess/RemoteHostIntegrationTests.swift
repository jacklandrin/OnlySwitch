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
        let host = RemoteHost.testing(
            catalog: [],
            router: router,
            pairingCode: "ABCDEFGH2345",
            revocationPrepared: { await gate.wait() }
        )
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let pairedClient = try await RemoteHostTestClient.connect(to: endpoint)
        try await pairedClient.pair(code: "ABCDEFGH2345")
        let identity = try await pairedClient.pairingIdentity()

        let revocation = Task { try await host.revoke(deviceID: identity.deviceID) }
        await gate.waitUntilEntered()
        let ordinaryClient = try await RemoteHostTestClient.connect(
            to: endpoint,
            deviceID: identity.deviceID
        )
        #expect(try await ordinaryClient.authenticate(credential: identity.credential) == .authenticated)

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
        let sendControl = AuthenticationResultSendControl()
        let host = RemoteHost.testing(
            catalog: [],
            router: router,
            pairingCode: "ABCDEFGH2345",
            authenticationResultWillSend: { try await sendControl.check() }
        )
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let originalClient = try await RemoteHostTestClient.connect(to: endpoint)
        try await originalClient.pair(code: "ABCDEFGH2345")
        let original = try await originalClient.pairingIdentity()
        try await host.revokePreservingCredentialForTesting(deviceID: original.deviceID)
        _ = await host.startPairing()
        await sendControl.failNextSend()
        let repairClient = try await RemoteHostTestClient.connect(to: endpoint, deviceID: original.deviceID)

        do {
            try await repairClient.pair(code: "ABCDEFGH2345")
            Issue.record("Expected the authentication result send to fail")
        } catch {}

        #expect(try await host.pairedDevices().first?.credential == original.credential)
        #expect(await host.isRevokedForTesting(deviceID: original.deviceID))
        #expect(try await host.revocationVerifierForTesting(deviceID: original.deviceID) == RemoteHandshakeCrypto.revocationVerifier(credential: original.credential))

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
        let sendControl = AuthenticationResultSendControl()
        let host = RemoteHost.testing(
            catalog: [],
            router: router,
            pairingCode: "ABCDEFGH2345",
            authenticationResultWillSend: { try await sendControl.check() }
        )
        let endpoint = try await host.startForTesting(port: 0)
        defer { Task { await host.stop() } }
        let originalClient = try await RemoteHostTestClient.connect(to: endpoint)
        try await originalClient.pair(code: "ABCDEFGH2345")
        let original = try await originalClient.pairingIdentity()
        try await host.revokePreservingCredentialForTesting(deviceID: original.deviceID)
        _ = await host.startPairing()
        let repairClient = try await RemoteHostTestClient.connect(to: endpoint, deviceID: original.deviceID)

        try await repairClient.pair(code: "ABCDEFGH2345")

        let repaired = try #require(try await host.pairedDevices().first)
        #expect(repaired.credential != original.credential)
        #expect(await host.isRevokedForTesting(deviceID: original.deviceID) == false)
        #expect(try await host.revocationVerifierForTesting(deviceID: original.deviceID) == nil)
        #expect(await sendControl.successfulChecks == 2)
    }

}

private enum AuthenticationResultSendFailure: Swift.Error { case injected }

private actor AuthenticationResultSendControl {
    private var shouldFail = false
    private(set) var successfulChecks = 0

    func failNextSend() { shouldFail = true }

    func check() throws {
        if shouldFail {
            shouldFail = false
            throw AuthenticationResultSendFailure.injected
        }
        successfulChecks += 1
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
