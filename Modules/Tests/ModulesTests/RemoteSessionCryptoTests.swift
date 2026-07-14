import CryptoKit
import Foundation
import Testing
@testable import RemoteCore
@testable import RemoteTransport

struct RemoteSessionCryptoTests {
    @Test func bothPeersDeriveMatchingDirectionalKeys() throws {
        let client = P256.KeyAgreement.PrivateKey()
        let server = P256.KeyAgreement.PrivateKey()
        let credential = Data(repeating: 7, count: 32)
        let transcript = Data("hello".utf8)

        let clientKeys = try RemoteSessionCrypto.deriveSessionKeys(
            role: .client,
            privateKey: client,
            peerPublicKey: server.publicKey.rawRepresentation,
            credential: credential,
            transcript: transcript
        )
        let serverKeys = try RemoteSessionCrypto.deriveSessionKeys(
            role: .server,
            privateKey: server,
            peerPublicKey: client.publicKey.rawRepresentation,
            credential: credential,
            transcript: transcript
        )

        #expect(keyData(clientKeys.send) == keyData(serverKeys.receive))
        #expect(keyData(clientKeys.receive) == keyData(serverKeys.send))
        #expect(keyData(clientKeys.send) != keyData(clientKeys.receive))
    }

    @Test func peersProduceMatchingPairingProofs() throws {
        let client = P256.KeyAgreement.PrivateKey()
        let server = P256.KeyAgreement.PrivateKey()
        let pairingCode = "23456789ABCD"
        let transcript = Data("pairing transcript".utf8)

        let clientProof = try RemoteSessionCrypto.makePairingProof(
            privateKey: client,
            peerPublicKey: server.publicKey.rawRepresentation,
            pairingCode: pairingCode,
            transcript: transcript
        )
        let serverProof = try RemoteSessionCrypto.makePairingProof(
            privateKey: server,
            peerPublicKey: client.publicKey.rawRepresentation,
            pairingCode: pairingCode,
            transcript: transcript
        )

        #expect(clientProof == serverProof)
        #expect(clientProof.count == 32)
    }

    @Test func encryptedMessageRoundTripsBetweenPeers() throws {
        let client = P256.KeyAgreement.PrivateKey()
        let server = P256.KeyAgreement.PrivateKey()
        let credential = Data(repeating: 7, count: 32)
        let transcript = Data("hello".utf8)
        let clientKeys = try RemoteSessionCrypto.deriveSessionKeys(
            role: .client,
            privateKey: client,
            peerPublicKey: server.publicKey.rawRepresentation,
            credential: credential,
            transcript: transcript
        )
        let serverKeys = try RemoteSessionCrypto.deriveSessionKeys(
            role: .server,
            privateKey: server,
            peerPublicKey: client.publicKey.rawRepresentation,
            credential: credential,
            transcript: transcript
        )
        let sender = RemoteSessionCrypto(sendKey: clientKeys.send, receiveKey: clientKeys.receive, noncePrefix: 7)
        let receiver = RemoteSessionCrypto(sendKey: serverKeys.send, receiveKey: serverKeys.receive, noncePrefix: 9)

        let sealed = try sender.seal(.ping(42))

        #expect(try receiver.open(sealed) == .ping(42))
    }

    @Test func replayedCounterIsRejected() throws {
        let sendKey = SymmetricKey(data: Data(repeating: 1, count: 32))
        let receiveKey = SymmetricKey(data: Data(repeating: 2, count: 32))
        let sender = RemoteSessionCrypto(sendKey: sendKey, receiveKey: receiveKey, noncePrefix: 7)
        let receiver = RemoteSessionCrypto(sendKey: receiveKey, receiveKey: sendKey, noncePrefix: 9)
        let sealed = try sender.seal(.ping(1))

        _ = try receiver.open(sealed)

        #expect(throws: RemoteProtocolError.self) {
            try receiver.open(sealed)
        }
    }

    @Test func aliasesShareMonotonicSendAndReplayState() throws {
        let sendKey = SymmetricKey(data: Data(repeating: 1, count: 32))
        let receiveKey = SymmetricKey(data: Data(repeating: 2, count: 32))
        let sender = RemoteSessionCrypto(sendKey: sendKey, receiveKey: receiveKey, noncePrefix: 7)
        let senderAlias = sender
        let receiver = RemoteSessionCrypto(sendKey: receiveKey, receiveKey: sendKey, noncePrefix: 9)
        let receiverAlias = receiver

        let first = try sender.seal(.ping(1))
        let second = try senderAlias.seal(.ping(2))

        #expect(first.counter == 0)
        #expect(second.counter == 1)
        #expect(try receiver.open(first) == .ping(1))
        #expect(try receiverAlias.open(second) == .ping(2))
        #expect(throws: RemoteProtocolError.self) {
            try receiver.open(first)
        }
    }

    @Test func tamperedCiphertextIsRejected() throws {
        let sendKey = SymmetricKey(data: Data(repeating: 1, count: 32))
        let receiveKey = SymmetricKey(data: Data(repeating: 2, count: 32))
        let sender = RemoteSessionCrypto(sendKey: sendKey, receiveKey: receiveKey, noncePrefix: 7)
        let receiver = RemoteSessionCrypto(sendKey: receiveKey, receiveKey: sendKey, noncePrefix: 9)
        let sealed = try sender.seal(.ping(1))
        var ciphertext = sealed.ciphertext
        ciphertext[ciphertext.startIndex] ^= 1
        let tampered = RemoteEncryptedFrame(
            noncePrefix: sealed.noncePrefix,
            counter: sealed.counter,
            ciphertext: ciphertext
        )

        #expect(throws: RemoteProtocolError.self) {
            try receiver.open(tampered)
        }
    }

    private func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
}

struct PairingCodeTests {
    @Test func generatedCodeHasExpectedLengthAndAlphabet() {
        var generator = IncrementingRandomNumberGenerator()

        let code = PairingCode.generate(using: &generator)

        #expect(code.count == 12)
        #expect(code.allSatisfy { "01OIL".contains($0) == false })
    }
}

private struct IncrementingRandomNumberGenerator: RandomNumberGenerator {
    private var value: UInt64 = 0

    mutating func next() -> UInt64 {
        defer { value &+= 1 }
        return value
    }
}
