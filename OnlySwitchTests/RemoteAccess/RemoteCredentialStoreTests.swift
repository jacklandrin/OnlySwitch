import Foundation
import RemoteTransport
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

    @Test func revocationPersistsOnlyDerivedVerifier() async throws {
        let store = RemoteCredentialStore.inMemory()
        let id = UUID()
        let credential = Data(repeating: 8, count: 32)
        try await store.save(.init(
            id: id,
            name: "iPhone",
            credential: credential,
            createdAt: .now,
            lastConnectedAt: nil
        ))

        #expect(try await store.revoke(id, matchingCredential: credential))

        #expect(try await store.load(id) == nil)
        let verifier = try #require(try await store.loadRevocationVerifier(id))
        #expect(verifier == RemoteHandshakeCrypto.revocationVerifier(credential: credential))
        #expect(verifier != credential)
    }

    @Test func staleConditionalRevocationCannotDeleteReplacementCredential() async throws {
        let store = RemoteCredentialStore.inMemory()
        let id = UUID()
        let oldCredential = Data(repeating: 1, count: 32)
        let newCredential = Data(repeating: 2, count: 32)
        try await store.save(.init(id: id, name: "iPhone", credential: newCredential, createdAt: .now, lastConnectedAt: nil))

        #expect(try await store.revoke(id, matchingCredential: oldCredential) == false)

        #expect(try await store.load(id)?.credential == newCredential)
        #expect(try await store.loadRevocationVerifier(id) == nil)
    }

    @Test func successfulRepairClearsPriorRevocationVerifier() async throws {
        let store = RemoteCredentialStore.inMemory()
        let id = UUID()
        let oldCredential = Data(repeating: 3, count: 32)
        let newCredential = Data(repeating: 4, count: 32)
        try await store.save(.init(id: id, name: "iPhone", credential: oldCredential, createdAt: .now, lastConnectedAt: nil))
        _ = try await store.revoke(id, matchingCredential: oldCredential)
        try await store.save(.init(id: id, name: "iPhone", credential: newCredential, createdAt: .now, lastConnectedAt: nil))

        try await store.finalizeRepair(deviceID: id, matchingCredential: newCredential)

        #expect(try await store.loadRevocationVerifier(id) == nil)
        #expect(try await store.load(id)?.credential == newCredential)
    }

    @Test func revocationVerifierSurvivesCredentialStoreRestart() async throws {
        let service = "RemoteCredentialStoreTests.\(UUID().uuidString)"
        let id = UUID()
        let credential = Data(repeating: 6, count: 32)
        let firstStore = RemoteCredentialStore.live(service: service)
        try await firstStore.save(.init(
            id: id,
            name: "iPad",
            credential: credential,
            createdAt: .now,
            lastConnectedAt: nil
        ))
        _ = try await firstStore.revoke(id, matchingCredential: credential)

        let restartedStore = RemoteCredentialStore.live(service: service)
        #expect(try await restartedStore.load(id) == nil)
        #expect(try await restartedStore.loadRevocationVerifier(id) == RemoteHandshakeCrypto.revocationVerifier(credential: credential))

        let replacement = Data(repeating: 7, count: 32)
        try await restartedStore.save(.init(id: id, name: "iPad", credential: replacement, createdAt: .now, lastConnectedAt: nil))
        try await restartedStore.finalizeRepair(deviceID: id, matchingCredential: replacement)
        try await restartedStore.delete(id)
    }
}
