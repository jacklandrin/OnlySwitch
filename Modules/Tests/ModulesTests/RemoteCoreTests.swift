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
        #expect(!RemoteProtocolVersion.current.isCompatible(with: .init(major: 1, minor: 7)))
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

        #expect(RemoteProtocolVersion.current == .init(major: 1, minor: 1))
        #expect(RemoteProtocolVersion.current.negotiated(with: legacy) == legacy)
        #expect(legacy.supportsAuthenticatedRevocation == false)
        #expect(RemoteProtocolVersion.current.supportsAuthenticatedRevocation)
        #expect(RemoteProtocolVersion.current.negotiated(with: future) == nil)
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
