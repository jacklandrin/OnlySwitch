import Foundation
import RemoteTransport
import Testing
@testable import RemoteCore

struct RemoteCoreTests {
    @Test func controlIDRoundTrips() throws {
        let value = RemoteControlID(kind: .evolution, value: UUID().uuidString)
        #expect(try JSONDecoder().decode(RemoteControlID.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test func actionMessageRoundTrips() throws {
        let request = RemoteActionRequest(
            requestID: UUID(),
            controlID: .init(kind: .builtIn, value: "2"),
            action: .setState(true)
        )
        let message = RemoteMessage.actionRequest(request)
        #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
    }

    @Test func majorCompatibilityRejectsDifferentMajor() {
        #expect(!RemoteProtocolVersion.current.isCompatible(with: .init(major: 2, minor: 0)))
        #expect(RemoteProtocolVersion.current.isCompatible(with: .init(major: 1, minor: 7)))
    }

    @Test func transactionalPairingRequiresMinorTwo() {
        #expect(!RemoteProtocolVersion(major: 1, minor: 1).supportsTransactionalPairing)
        #expect(RemoteProtocolVersion(major: 1, minor: 2).supportsTransactionalPairing)
        #expect(RemoteProtocolVersion.current == .init(major: 1, minor: 2))
    }

    @Test func pairingTransactionMessagesRoundTrip() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000912")!
        let prepared = PairingPrepared(
            transactionID: id,
            macID: UUID(uuidString: "00000000-0000-0000-0000-000000000913")!,
            credential: Data(repeating: 7, count: 32),
            catalogRevision: 4,
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        for message in [
            RemoteMessage.pairingPrepared(prepared),
            .pairingCommit(.init(transactionID: id)),
            .pairingAbort(.init(transactionID: id)),
            .pairingStatusRequest(.init(transactionID: id)),
            .pairingStatus(.init(transactionID: id, state: .prepared)),
            .pairingCommitted(.init(transactionID: id)),
        ] {
            #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
        }
    }

    @Test func authenticatedRevocationMessageRoundTrips() throws {
        let message = RemoteMessage.credentialRevoked
        #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
    }

    @Test func offlineRevocationProofRoundTrips() throws {
        let proof = CredentialRevocationProof(deviceID: UUID(), proof: Data(repeating: 9, count: 32))
        let message = RemoteMessage.credentialRevocationProof(proof)

        #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
    }

    @Test func protocolMinorNegotiatesWithoutSendingNewMessagesToLegacyPeers() {
        let legacy = RemoteProtocolVersion(major: 1, minor: 0)
        let future = RemoteProtocolVersion(major: 1, minor: 2)

        #expect(RemoteProtocolVersion.current == .init(major: 1, minor: 2))
        #expect(RemoteProtocolVersion.current.negotiated(with: legacy) == legacy)
        #expect(legacy.supportsAuthenticatedRevocation == false)
        #expect(RemoteProtocolVersion.current.supportsAuthenticatedRevocation)
        #expect(RemoteProtocolVersion.current.negotiated(with: future) == .current)
        #expect(future.negotiated(with: RemoteProtocolVersion(major: 1, minor: 0)) == .init(major: 1, minor: 0))
        #expect(RemoteProtocolVersion.current.negotiated(with: .init(major: 2, minor: 0)) == nil)
    }

    @Test func offlineRevocationProofIsBoundToFreshHandshakeTranscript() {
        let credential = Data(repeating: 4, count: 32)
        let verifier = RemoteHandshakeCrypto.revocationVerifier(credential: credential)
        let firstTranscript = Data("first-fresh-transcript".utf8)
        let secondTranscript = Data("second-fresh-transcript".utf8)
        let proof = RemoteHandshakeCrypto.revocationProof(verifier: verifier, transcript: firstTranscript)

        #expect(verifier != credential)
        #expect(RemoteHandshakeCrypto.verifyRevocationProof(proof, verifier: verifier, transcript: firstTranscript))
        #expect(!RemoteHandshakeCrypto.verifyRevocationProof(proof, verifier: verifier, transcript: secondTranscript))
        #expect(!RemoteHandshakeCrypto.verifyRevocationProof(Data(repeating: 0, count: 32), verifier: verifier, transcript: firstTranscript))
    }
}
