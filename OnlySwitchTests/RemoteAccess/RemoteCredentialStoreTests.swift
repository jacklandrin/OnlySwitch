import Foundation
import Testing
@testable import OnlySwitch

struct RemoteCredentialStoreTests {
    @Test
    func revokingOneDevicePreservesOtherCredentials() async throws {
        let store = RemoteCredentialStore.inMemory()
        let firstID = UUID()
        let secondID = UUID()
        try await store.save(.init(
            id: firstID,
            name: "iPhone",
            credential: Data(repeating: 1, count: 32),
            createdAt: .now,
            lastConnectedAt: nil
        ))
        try await store.save(.init(
            id: secondID,
            name: "iPad",
            credential: Data(repeating: 2, count: 32),
            createdAt: .now,
            lastConnectedAt: nil
        ))

        try await store.delete(firstID)

        #expect(try await store.load(firstID) == nil)
        #expect(try await store.load(secondID)?.name == "iPad")
        #expect(try await store.loadAll().map(\.id) == [secondID])
    }

    @Test
    func rejectsCredentialsThatAreNot256Bits() async {
        let store = RemoteCredentialStore.inMemory()
        let invalid = PairedRemoteDevice(
            id: UUID(),
            name: "iPhone",
            credential: Data(repeating: 1, count: 31),
            createdAt: .now,
            lastConnectedAt: nil
        )

        await #expect(throws: RemoteCredentialStore.Error.invalidCredential) {
            try await store.save(invalid)
        }
    }

    @Test
    func installationIdentityIsStableWithinStore() async throws {
        let store = RemoteCredentialStore.inMemory()
        let first = try await store.installationID()
        let second = try await store.installationID()

        #expect(first == second)
    }
}
