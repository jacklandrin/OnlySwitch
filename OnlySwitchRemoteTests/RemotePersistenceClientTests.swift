import Foundation
import RemoteCore
import Testing
@testable import OnlySwitchRemote

struct RemotePersistenceClientTests {
    private let firstMac = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let secondMac = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test func layoutsRemainIndependentPerMac() async throws {
        let client = RemotePersistenceClient.inMemory()
        try await client.saveLayout(.init(macID: firstMac, selectedControlIDs: [.darkMode], order: [.darkMode]))
        try await client.saveLayout(.init(macID: secondMac, selectedControlIDs: [.mute], order: [.mute]))

        #expect(try await client.loadLayout(firstMac)?.selectedControlIDs == [.darkMode])
        #expect(try await client.loadLayout(secondMac)?.selectedControlIDs == [.mute])
    }

    @Test func forgettingOneMacPreservesOtherMacData() async throws {
        let client = RemotePersistenceClient.inMemory()
        try await client.savePairedMacs([
            .init(id: firstMac, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false),
            .init(id: secondMac, displayName: "Laptop", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false),
        ])
        try await client.saveLayout(.init(macID: firstMac, selectedControlIDs: [.darkMode], order: [.darkMode]))
        try await client.saveLayout(.init(macID: secondMac, selectedControlIDs: [.mute], order: [.mute]))
        try await client.saveSelectedMacID(firstMac)

        try await client.forgetMac(firstMac)

        #expect(try await client.loadPairedMacs().map(\.id) == [secondMac])
        #expect(try await client.loadLayout(firstMac) == nil)
        #expect(try await client.loadLayout(secondMac)?.selectedControlIDs == [.mute])
        #expect(try await client.loadSelectedMacID() == nil)
    }

    @Test func keychainRejectsCredentialsThatAreNotThirtyTwoBytes() async {
        let keychain = RemoteKeychainClient.inMemory()

        await #expect(throws: RemoteKeychainClient.Error.invalidCredentialLength) {
            try await keychain.saveCredential(firstMac, Data(repeating: 7, count: 31))
        }
        let stored = try? await keychain.loadCredential(firstMac)
        #expect(stored == nil)
    }
}
