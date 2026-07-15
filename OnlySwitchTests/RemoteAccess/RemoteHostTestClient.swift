import Foundation
import CryptoKit
import Network
import RemoteCore
import RemoteTransport
@testable import OnlySwitch

actor RemoteHostTestClient {
    private let io: RemoteConnectionIO
    private let deviceID = UUID()
    private let deviceName = "Integration Test iPhone"
    private var clientKey: P256.KeyAgreement.PrivateKey?
    private var serverHello: ServerHello?
    private var transcript: Data?
    private var crypto: RemoteSessionCrypto?

    static func connect(to endpoint: NWEndpoint) async throws -> RemoteHostTestClient {
        try await RemoteHostTestClient(endpoint: endpoint)
    }

    private init(endpoint: NWEndpoint) async throws {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let io = RemoteConnectionIO(connection: connection)
        self.io = io
        try await io.start()
    }

    func pair(code: String) async throws {
        let key = P256.KeyAgreement.PrivateKey()
        let hello = ClientHello(
            version: .current,
            deviceID: deviceID,
            deviceName: deviceName,
            ephemeralPublicKey: key.publicKey.rawRepresentation
        )
        try await io.send(.plaintext(.clientHello(hello)))
        let response = try await io.receive()
        guard response.kind == .plaintext, case let .serverHello(server)? = response.plaintext else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Missing server hello")
        }
        let transcript = try RemoteHandshake.transcript(client: hello, server: server)
        self.clientKey = key
        self.serverHello = server
        self.transcript = transcript
        try await io.send(.plaintext(.pairingRequest))
        let proof = try RemoteSessionCrypto.makePairingProof(
            privateKey: key,
            peerPublicKey: server.ephemeralPublicKey,
            pairingCode: code,
            transcript: transcript
        )
        try await io.send(.plaintext(.pairingProof(.init(deviceID: deviceID, proof: proof))))

        do {
            let protectedResult = try await io.receive()
            let pairingCrypto = try makeCrypto(credential: Data(code.utf8), key: key, server: server, transcript: transcript)
            guard protectedResult.kind == .encrypted, let frame = protectedResult.encrypted,
                  case let .pairingResult(result) = try pairingCrypto.open(frame),
                  case let .success(success) = result else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing failed")
            }
            let sessionCrypto = try makeCrypto(credential: success.credential, key: key, server: server, transcript: transcript)
            crypto = sessionCrypto
            let authentication = AuthenticationProof(
                deviceID: deviceID,
                proof: RemoteHandshake.authenticationProof(credential: success.credential, transcript: transcript)
            )
            try await io.send(.encrypted(try sessionCrypto.seal(.authenticationProof(authentication))))
            guard case let .authenticationResult(authenticationResult) = try await receiveEncrypted(),
                  case .success = authenticationResult else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Authentication failed")
            }
        } catch let error as RemoteProtocolError {
            throw error
        } catch {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing failed")
        }
    }

    func catalog() async throws -> [RemoteControlDescriptor] {
        try await sendEncrypted(.catalogRequest)
        while true {
            switch try await receiveEncrypted() {
            case let .catalogSnapshot(_, controls): return controls
            case .statusChanged, .statusSnapshot: continue
            default: throw RemoteProtocolError(code: .invalidFrame, message: "Unexpected catalog response")
            }
        }
    }

    func subscribe(_ ids: Set<RemoteControlID>) async throws {
        try await sendEncrypted(.subscriptionUpdate(ids))
    }

    func nextStatus(for id: RemoteControlID) async throws -> RemoteControlStatus {
        while true {
            switch try await receiveEncrypted() {
            case let .statusChanged(status) where status.id == id: return status
            case let .statusSnapshot(statuses):
                if let status = statuses.first(where: { $0.id == id }) { return status }
            default: continue
            }
        }
    }

    func send(_ request: RemoteActionRequest) async throws -> RemoteActionResult {
        try await sendEncrypted(.actionRequest(request))
        while true {
            switch try await receiveEncrypted() {
            case let .actionResult(result) where result.requestID == request.requestID: return result
            case .statusChanged, .statusSnapshot: continue
            default: throw RemoteProtocolError(code: .invalidFrame, message: "Unexpected action response")
            }
        }
    }

    func nextMessage() async throws -> RemoteMessage {
        try await receiveEncrypted()
    }

    private func sendEncrypted(_ message: RemoteMessage) async throws {
        guard let crypto else { throw RemoteProtocolError(code: .authenticationFailed, message: "Not paired") }
        try await io.send(.encrypted(try crypto.seal(message)))
    }

    private func receiveEncrypted() async throws -> RemoteMessage {
        guard let crypto else { throw RemoteProtocolError(code: .authenticationFailed, message: "Not paired") }
        let packet = try await io.receive()
        guard packet.kind == .encrypted, let frame = packet.encrypted else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Expected encrypted packet")
        }
        return try crypto.open(frame)
    }

    private func makeCrypto(
        credential: Data,
        key: P256.KeyAgreement.PrivateKey,
        server: ServerHello,
        transcript: Data
    ) throws -> RemoteSessionCrypto {
        let keys = try RemoteSessionCrypto.deriveSessionKeys(
            role: .client,
            privateKey: key,
            peerPublicKey: server.ephemeralPublicKey,
            credential: credential,
            transcript: transcript
        )
        return RemoteSessionCrypto(
            sendKey: keys.send,
            receiveKey: keys.receive,
            noncePrefix: UInt32.random(in: .min ... .max)
        )
    }
}
