import Foundation
import CryptoKit
import Network
import RemoteCore
import RemoteTransport
@testable import OnlySwitch

actor RemoteHostTestClient {
    enum AuthenticationOutcome: Equatable { case authenticated, revoked }

    private let io: RemoteConnectionIO
    private let deviceID: UUID
    private let version: RemoteProtocolVersion
    private let deviceName = "Integration Test iPhone"
    private var clientKey: P256.KeyAgreement.PrivateKey?
    private var serverHello: ServerHello?
    private var transcript: Data?
    private var crypto: RemoteSessionCrypto?
    private var credential: Data?
    private(set) var authenticatedCatalogRevision: UInt64?

    var id: UUID { deviceID }

    static func connect(
        to endpoint: NWEndpoint,
        deviceID: UUID = UUID(),
        version: RemoteProtocolVersion = .current
    ) async throws -> RemoteHostTestClient {
        try await RemoteHostTestClient(endpoint: endpoint, deviceID: deviceID, version: version)
    }

    private init(endpoint: NWEndpoint, deviceID: UUID, version: RemoteProtocolVersion) async throws {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let io = RemoteConnectionIO(connection: connection)
        self.io = io
        self.deviceID = deviceID
        self.version = version
        try await io.start()
    }

    func pair(code: String) async throws {
        let prepared = try await preparePairing(code: code)
        try await sendTransaction(.pairingCommit(.init(transactionID: prepared.transactionID)))
        guard try await receiveTransactionStatus().state == .committed else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing was not committed")
        }
        authenticatedCatalogRevision = prepared.catalogRevision
    }

    func preparePairing(code: String) async throws -> PairingPrepared {
        let key = P256.KeyAgreement.PrivateKey()
        let hello = ClientHello(
            version: version,
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
                  case let .pairingPrepared(prepared) = try pairingCrypto.open(frame),
                  prepared.credential.count == 32 else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing failed")
            }
            let sessionCrypto = try makeCrypto(
                credential: prepared.credential,
                key: key,
                server: server,
                transcript: transcript
            )
            crypto = sessionCrypto
            credential = prepared.credential
            let authentication = AuthenticationProof(
                deviceID: deviceID,
                proof: RemoteHandshake.authenticationProof(
                    credential: prepared.credential,
                    transcript: transcript
                )
            )
            try await io.send(.encrypted(try sessionCrypto.seal(.authenticationProof(authentication))))
            return prepared
        } catch let error as RemoteProtocolError {
            throw error
        } catch {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing failed")
        }
    }

    func pairingIdentity() throws -> (deviceID: UUID, credential: Data) {
        guard let credential else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Client is not paired")
        }
        return (deviceID, credential)
    }

    func authenticate(credential: Data) async throws -> AuthenticationOutcome {
        let key = P256.KeyAgreement.PrivateKey()
        let hello = ClientHello(
            version: version,
            deviceID: deviceID,
            deviceName: deviceName,
            ephemeralPublicKey: key.publicKey.rawRepresentation
        )
        try await io.send(.plaintext(.clientHello(hello)))
        guard case let .serverHello(server)? = (try await io.receive()).plaintext else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Missing server hello")
        }
        let transcript = try RemoteHandshake.transcript(client: hello, server: server)
        let crypto = try makeCrypto(credential: credential, key: key, server: server, transcript: transcript)
        let proof = AuthenticationProof(
            deviceID: deviceID,
            proof: RemoteHandshake.authenticationProof(credential: credential, transcript: transcript)
        )
        try await io.send(.encrypted(try crypto.seal(.authenticationProof(proof))))
        let response = try await io.receive()
        if case let .credentialRevocationProof(revocation)? = response.plaintext {
            let verifier = RemoteHandshake.revocationVerifier(credential: credential)
            guard revocation.deviceID == deviceID,
                  RemoteHandshake.verifyRevocationProof(
                    revocation.proof,
                    verifier: verifier,
                    transcript: transcript
                  ) else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Invalid revocation proof")
            }
            return .revoked
        }
        guard let frame = response.encrypted,
              case let .authenticationResult(result) = try crypto.open(frame),
              case let .success(success) = result else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Authentication failed")
        }
        self.crypto = crypto
        self.credential = credential
        authenticatedCatalogRevision = success.catalogRevision
        return .authenticated
    }

    func catalog() async throws -> [RemoteControlDescriptor] {
        (try await catalogSnapshot()).controls
    }

    func catalogSnapshot() async throws -> RemoteCatalogSnapshot {
        try await sendEncrypted(.catalogRequest)
        while true {
            switch try await receiveEncrypted() {
            case let .catalogSnapshot(revision, controls):
                return RemoteCatalogSnapshot(revision: revision, controls: controls)
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

    func sendTransaction(_ message: RemoteMessage) async throws {
        switch message {
        case .pairingCommit, .pairingAbort, .pairingStatusRequest:
            try await sendEncrypted(message)
        default:
            throw RemoteProtocolError(code: .invalidFrame, message: "Expected pairing transaction command")
        }
    }

    func receiveTransactionStatus() async throws -> PairingTransactionStatus {
        switch try await receiveEncrypted() {
        case let .pairingStatus(status):
            return status
        case let .pairingCommitted(command):
            return .init(transactionID: command.transactionID, state: .committed)
        default:
            throw RemoteProtocolError(code: .invalidFrame, message: "Expected pairing transaction status")
        }
    }

    func close() async {
        await io.cancel()
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
