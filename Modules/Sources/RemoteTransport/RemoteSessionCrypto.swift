import CryptoKit
import Foundation
import os
import RemoteCore

public enum RemotePeerRole: Sendable {
    case client
    case server
}

public struct RemoteDirectionalKeys: Sendable {
    public let send: SymmetricKey
    public let receive: SymmetricKey

    public init(send: SymmetricKey, receive: SymmetricKey) {
        self.send = send
        self.receive = receive
    }
}

public struct RemoteEncryptedFrame: Codable, Equatable, Sendable {
    public let noncePrefix: UInt32
    public let counter: UInt64
    public let ciphertext: Data

    public init(noncePrefix: UInt32, counter: UInt64, ciphertext: Data) {
        self.noncePrefix = noncePrefix
        self.counter = counter
        self.ciphertext = ciphertext
    }
}

public final class RemoteSessionCrypto: Sendable {
    private static let authenticationTagSize = 16
    private static let pairingLabel = Data("OnlySwitch Remote pairing proof v1".utf8)
    private static let clientToServerLabel = Data("OnlySwitch Remote client-to-server v1".utf8)
    private static let serverToClientLabel = Data("OnlySwitch Remote server-to-client v1".utf8)

    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private let noncePrefix: UInt32
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var nextSendCounter: UInt64? = 0
        var lastReceivedCounter: UInt64?
    }

    public init(sendKey: SymmetricKey, receiveKey: SymmetricKey, noncePrefix: UInt32) {
        self.sendKey = sendKey
        self.receiveKey = receiveKey
        self.noncePrefix = noncePrefix
    }

    public static func makePairingProof(
        privateKey: P256.KeyAgreement.PrivateKey,
        peerPublicKey: Data,
        pairingCode: String,
        transcript: Data
    ) throws -> Data {
        let sharedSecret = try sharedSecret(privateKey: privateKey, peerPublicKey: peerPublicKey)
        var sharedInfo = pairingLabel
        sharedInfo.append(transcript)
        let pairingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(pairingCode.utf8),
            sharedInfo: sharedInfo,
            outputByteCount: 32
        )
        return Data(HMAC<SHA256>.authenticationCode(for: transcript, using: pairingKey))
    }

    public static func deriveSessionKeys(
        role: RemotePeerRole,
        privateKey: P256.KeyAgreement.PrivateKey,
        peerPublicKey: Data,
        credential: Data,
        transcript: Data
    ) throws -> RemoteDirectionalKeys {
        let sharedSecret = try sharedSecret(privateKey: privateKey, peerPublicKey: peerPublicKey)
        let clientToServer = deriveKey(
            from: sharedSecret,
            credential: credential,
            transcript: transcript,
            label: clientToServerLabel
        )
        let serverToClient = deriveKey(
            from: sharedSecret,
            credential: credential,
            transcript: transcript,
            label: serverToClientLabel
        )

        switch role {
        case .client:
            return RemoteDirectionalKeys(send: clientToServer, receive: serverToClient)
        case .server:
            return RemoteDirectionalKeys(send: serverToClient, receive: clientToServer)
        }
    }

    public func seal(_ message: RemoteMessage) throws -> RemoteEncryptedFrame {
        try state.withLock { state in
            guard let counter = state.nextSendCounter else {
                throw Self.invalidFrame("The session nonce counter is exhausted.")
            }

            let nonce = try AES.GCM.Nonce(data: Self.nonce(prefix: noncePrefix, counter: counter))
            let plaintext = try JSONEncoder().encode(message)
            let sealedBox = try AES.GCM.seal(
                plaintext,
                using: sendKey,
                nonce: nonce,
                authenticating: Self.authenticatedHeader(prefix: noncePrefix, counter: counter)
            )
            var ciphertext = sealedBox.ciphertext
            ciphertext.append(sealedBox.tag)

            state.nextSendCounter = counter == UInt64.max ? nil : counter + 1
            return RemoteEncryptedFrame(noncePrefix: noncePrefix, counter: counter, ciphertext: ciphertext)
        }
    }

    public func open(_ frame: RemoteEncryptedFrame) throws -> RemoteMessage {
        try state.withLock { state in
            guard state.lastReceivedCounter.map({ frame.counter > $0 }) ?? true else {
                throw RemoteProtocolError(code: .replayDetected, message: "Frame counter is not strictly increasing.")
            }
            guard frame.ciphertext.count >= Self.authenticationTagSize else {
                throw Self.invalidFrame("Encrypted frame is missing its authentication tag.")
            }

            do {
                let nonce = try AES.GCM.Nonce(data: Self.nonce(prefix: frame.noncePrefix, counter: frame.counter))
                let tagStart = frame.ciphertext.count - Self.authenticationTagSize
                let sealedBox = try AES.GCM.SealedBox(
                    nonce: nonce,
                    ciphertext: frame.ciphertext.prefix(tagStart),
                    tag: frame.ciphertext.suffix(Self.authenticationTagSize)
                )
                let plaintext = try AES.GCM.open(
                    sealedBox,
                    using: receiveKey,
                    authenticating: Self.authenticatedHeader(prefix: frame.noncePrefix, counter: frame.counter)
                )
                let message = try JSONDecoder().decode(RemoteMessage.self, from: plaintext)
                state.lastReceivedCounter = frame.counter
                return message
            } catch {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Encrypted frame authentication failed.")
            }
        }
    }

    private static func sharedSecret(
        privateKey: P256.KeyAgreement.PrivateKey,
        peerPublicKey: Data
    ) throws -> SharedSecret {
        let publicKey = try P256.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        return try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
    }

    private static func deriveKey(
        from sharedSecret: SharedSecret,
        credential: Data,
        transcript: Data,
        label: Data
    ) -> SymmetricKey {
        var sharedInfo = label
        sharedInfo.append(transcript)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: credential,
            sharedInfo: sharedInfo,
            outputByteCount: 32
        )
    }

    private static func nonce(prefix: UInt32, counter: UInt64) -> Data {
        authenticatedHeader(prefix: prefix, counter: counter)
    }

    private static func authenticatedHeader(prefix: UInt32, counter: UInt64) -> Data {
        var prefix = prefix.bigEndian
        var counter = counter.bigEndian
        var data = withUnsafeBytes(of: &prefix) { Data($0) }
        data.append(withUnsafeBytes(of: &counter) { Data($0) })
        return data
    }

    private static func invalidFrame(_ message: String) -> RemoteProtocolError {
        RemoteProtocolError(code: .invalidFrame, message: message)
    }
}
