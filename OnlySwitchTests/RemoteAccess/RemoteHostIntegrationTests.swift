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
}
