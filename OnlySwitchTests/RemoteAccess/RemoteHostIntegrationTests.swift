import Foundation
import RemoteCore
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
