import CryptoKit
import Foundation
import Network
import RemoteCore
import RemoteTransport

struct RemoteWirePacket: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case plaintext, encrypted }

    let kind: Kind
    let plaintext: RemoteMessage?
    let encrypted: RemoteEncryptedFrame?

    static func plaintext(_ message: RemoteMessage) -> Self {
        Self(kind: .plaintext, plaintext: message, encrypted: nil)
    }

    static func encrypted(_ frame: RemoteEncryptedFrame) -> Self {
        Self(kind: .encrypted, plaintext: nil, encrypted: frame)
    }

    func validated() throws -> Self {
        guard (kind == .plaintext && plaintext != nil && encrypted == nil)
                || (kind == .encrypted && encrypted != nil && plaintext == nil) else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Invalid wire envelope")
        }
        return self
    }
}

enum RemoteHandshake {
    static func transcript(client: ClientHello, server: ServerHello) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(client)
        data.append(0)
        data.append(try encoder.encode(server))
        return data
    }

    static func authenticationProof(credential: Data, transcript: Data) -> Data {
        var input = Data("OnlySwitch Remote client authentication v1".utf8)
        input.append(transcript)
        return Data(HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: credential)))
    }

    static func verifyAuthenticationProof(_ proof: Data, credential: Data, transcript: Data) -> Bool {
        return HMAC<SHA256>.isValidAuthenticationCode(
            proof,
            authenticating: Data("OnlySwitch Remote client authentication v1".utf8) + transcript,
            using: SymmetricKey(data: credential)
        )
    }
}

actor RemoteConnectionIO {
    enum Error: Swift.Error { case closed, incompleteFrame }

    static let maximumPayloadSize = 4 * 1_024 * 1_024
    let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                let gate = ContinuationGate(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: gate.resume(returning: ())
                    case let .failed(error): gate.resume(throwing: error)
                    case .cancelled: gate.resume(throwing: CancellationError())
                    default: break
                    }
                }
                connection.start(queue: .global(qos: .userInitiated))
            }
        } onCancel: {
            connection.cancel()
        }
    }

    func send(_ packet: RemoteWirePacket) async throws {
        let payload = try JSONEncoder().encode(packet.validated())
        guard payload.count <= Self.maximumPayloadSize else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Frame exceeds 4 MiB")
        }
        var size = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }
        frame.append(payload)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                connection.send(content: frame, completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                })
            }
        } onCancel: {
            connection.cancel()
        }
    }

    func receive() async throws -> RemoteWirePacket {
        let header = try await receiveExactly(4)
        let count = header.reduce(0) { ($0 << 8) | Int($1) }
        guard count <= Self.maximumPayloadSize else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Frame exceeds 4 MiB")
        }
        let body = try await receiveExactly(count)
        do {
            return try JSONDecoder().decode(RemoteWirePacket.self, from: body).validated()
        } catch let error as RemoteProtocolError {
            throw error
        } catch {
            throw RemoteProtocolError(code: .invalidFrame, message: "Frame could not be decoded")
        }
    }

    func cancel() { connection.cancel() }

    private func receiveExactly(_ count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        var result = Data()
        while result.count < count {
            let remaining = count - result.count
            let part = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Swift.Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) {
                        data, _, isComplete, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let data, data.isEmpty == false { continuation.resume(returning: data) }
                        else if isComplete { continuation.resume(throwing: Error.closed) }
                        else { continuation.resume(throwing: Error.incompleteFrame) }
                    }
                }
            } onCancel: {
                connection.cancel()
            }
            result.append(part)
        }
        return result
    }
}

final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Swift.Error>?

    init(_ continuation: CheckedContinuation<Void, Swift.Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Void) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Swift.Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Void, Swift.Error>? {
        lock.lock()
        defer { lock.unlock() }
        defer { continuation = nil }
        return continuation
    }
}

actor RemotePeerSession {
    enum State: Sendable { case awaitingHello, awaitingPairOrAuthentication, authenticated(UUID), closed }

    let id: UUID
    private let io: RemoteConnectionIO
    private let macID: UUID
    private let macName: String
    private let credentialStore: RemoteCredentialStore
    private let catalogProvider: RemoteCatalogProvider
    private let router: RemoteCommandRouter
    private let pairingWindow: @Sendable () async -> PairingWindow?
    private let pairingFailed: @Sendable () async -> Void
    private let consumePairing: @Sendable (String) async -> Bool
    private let subscriptionsChanged: @Sendable (UUID, Set<RemoteControlID>, @escaping RemoteStatusScheduler.Sink) async -> Void
    private let refreshRequested: @Sendable (RemoteControlID) async -> Void
    private let authenticated: @Sendable (UUID, UUID) async -> Bool
    private let ended: @Sendable (UUID) async -> Void
    private var state: State = .awaitingHello
    private var crypto: RemoteSessionCrypto?

    init(
        id: UUID = UUID(),
        connection: NWConnection,
        macID: UUID,
        macName: String,
        credentialStore: RemoteCredentialStore,
        catalogProvider: RemoteCatalogProvider,
        router: RemoteCommandRouter,
        pairingWindow: @escaping @Sendable () async -> PairingWindow?,
        pairingFailed: @escaping @Sendable () async -> Void,
        consumePairing: @escaping @Sendable (String) async -> Bool,
        subscriptionsChanged: @escaping @Sendable (UUID, Set<RemoteControlID>, @escaping RemoteStatusScheduler.Sink) async -> Void,
        refreshRequested: @escaping @Sendable (RemoteControlID) async -> Void,
        authenticated: @escaping @Sendable (UUID, UUID) async -> Bool,
        ended: @escaping @Sendable (UUID) async -> Void
    ) {
        self.id = id
        self.io = RemoteConnectionIO(connection: connection)
        self.macID = macID
        self.macName = macName
        self.credentialStore = credentialStore
        self.catalogProvider = catalogProvider
        self.router = router
        self.pairingWindow = pairingWindow
        self.pairingFailed = pairingFailed
        self.consumePairing = consumePairing
        self.subscriptionsChanged = subscriptionsChanged
        self.refreshRequested = refreshRequested
        self.authenticated = authenticated
        self.ended = ended
    }

    func run() async {
        do {
            try await io.start()
            try await handshake()
            try await messageLoop()
        } catch {
            // Protocol and network failures intentionally close without exposing secrets.
        }
        state = .closed
        await io.cancel()
        await ended(id)
    }

    func close() async {
        state = .closed
        await io.cancel()
    }

    func sendStatus(_ status: RemoteControlStatus) async {
        try? await sendEncrypted(.statusChanged(status))
    }

    private func handshake() async throws {
        let first = try await io.receive()
        guard first.kind == .plaintext, case let .clientHello(client)? = first.plaintext else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Client hello required")
        }
        guard client.version.isCompatible(with: .current) else {
            try? await io.send(.plaintext(.sessionError(.init(
                code: .upgradeRequired,
                message: "A compatible OnlySwitch version is required"
            ))))
            throw RemoteProtocolError(code: .upgradeRequired, message: "Incompatible protocol")
        }
        guard client.deviceName.utf8.count <= 128,
              client.deviceName.isEmpty == false,
              client.deviceName.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) == false }) else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Invalid device name")
        }
        let serverKey = P256.KeyAgreement.PrivateKey()
        let server = ServerHello(
            version: .current,
            macID: macID,
            macName: macName,
            ephemeralPublicKey: serverKey.publicKey.rawRepresentation,
            challenge: Self.randomData(count: 32)
        )
        try await io.send(.plaintext(.serverHello(server)))
        state = .awaitingPairOrAuthentication
        let transcript = try RemoteHandshake.transcript(client: client, server: server)
        let next = try await io.receive()

        let credential: Data
        if next.kind == .plaintext, next.plaintext == .pairingRequest {
            credential = try await completePairing(
                client: client,
                serverKey: serverKey,
                transcript: transcript
            )
        } else {
            guard let stored = try await credentialStore.load(client.deviceID) else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing required")
            }
            credential = stored.credential
            crypto = try Self.makeCrypto(
                role: .server,
                privateKey: serverKey,
                peerKey: client.ephemeralPublicKey,
                credential: credential,
                transcript: transcript
            )
            try await authenticate(packet: next, client: client, credential: credential, transcript: transcript)
        }

        if crypto == nil {
            crypto = try Self.makeCrypto(
                role: .server,
                privateKey: serverKey,
                peerKey: client.ephemeralPublicKey,
                credential: credential,
                transcript: transcript
            )
            try await authenticate(packet: try await io.receive(), client: client, credential: credential, transcript: transcript)
        }
    }

    private func completePairing(
        client: ClientHello,
        serverKey: P256.KeyAgreement.PrivateKey,
        transcript: Data
    ) async throws -> Data {
        guard let window = await pairingWindow(), window.expiresAt > Date() else {
            throw RemoteProtocolError(code: .pairingExpired, message: "Pairing code expired")
        }
        let proofPacket = try await io.receive()
        guard proofPacket.kind == .plaintext,
              case let .pairingProof(pairingProof)? = proofPacket.plaintext,
              pairingProof.deviceID == client.deviceID else {
            await pairingFailed()
            throw RemoteProtocolError(code: .authenticationFailed, message: "Invalid pairing proof")
        }
        let expected: Data
        do {
            expected = try RemoteSessionCrypto.makePairingProof(
                privateKey: serverKey,
                peerPublicKey: client.ephemeralPublicKey,
                pairingCode: window.code,
                transcript: transcript
            )
        } catch {
            await pairingFailed()
            throw RemoteProtocolError(code: .authenticationFailed, message: "Invalid pairing proof")
        }
        guard Self.constantTimeEqual(pairingProof.proof, expected) else {
            await pairingFailed()
            throw RemoteProtocolError(code: .authenticationFailed, message: "Invalid pairing proof")
        }
        guard await consumePairing(window.code) else {
            throw RemoteProtocolError(code: .pairingExpired, message: "Pairing code expired")
        }

        let credential = Self.randomData(count: 32)
        let record = PairedRemoteDevice(
            id: client.deviceID,
            name: client.deviceName,
            credential: credential,
            createdAt: .now,
            lastConnectedAt: nil
        )
        try await credentialStore.save(record)

        let pairingCrypto = try Self.makeCrypto(
            role: .server,
            privateKey: serverKey,
            peerKey: client.ephemeralPublicKey,
            credential: Data(window.code.utf8),
            transcript: transcript
        )
        let protectedResult = try pairingCrypto.seal(.pairingResult(.success(.init(macID: macID, credential: credential))))
        try await io.send(.encrypted(protectedResult))
        return credential
    }

    private func authenticate(
        packet: RemoteWirePacket,
        client: ClientHello,
        credential: Data,
        transcript: Data
    ) async throws {
        guard let crypto, packet.kind == .encrypted, let frame = packet.encrypted,
              case let .authenticationProof(proof) = try crypto.open(frame),
              proof.deviceID == client.deviceID,
              RemoteHandshake.verifyAuthenticationProof(proof.proof, credential: credential, transcript: transcript) else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Authentication failed")
        }
        _ = try await credentialStore.markConnected(
            deviceID: client.deviceID,
            credential: credential,
            at: .now
        )
        guard await authenticated(id, client.deviceID) else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Credential was revoked")
        }
        state = .authenticated(client.deviceID)
        try await sendEncrypted(.authenticationResult(.success(.init(sessionID: id, catalogRevision: 1))))
    }

    private func messageLoop() async throws {
        while case .authenticated = state {
            let packet = try await io.receive()
            guard packet.kind == .encrypted, let frame = packet.encrypted, let crypto else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Encrypted session required")
            }
            let message = try crypto.open(frame)
            switch message {
            case .catalogRequest:
                let catalog = try await catalogProvider.catalog()
                guard catalog.allSatisfy({ descriptor in
                    if case let .png(data) = descriptor.icon { return data.count <= 256 * 1_024 }
                    return true
                }) else {
                    throw RemoteProtocolError(code: .invalidFrame, message: "Catalog icon exceeds 256 KiB")
                }
                try await sendEncrypted(.catalogSnapshot(revision: 1, controls: catalog))
            case let .subscriptionUpdate(ids):
                await subscriptionsChanged(id, ids) { [weak self] status in
                    await self?.sendStatus(status)
                }
            case let .actionRequest(request):
                let result = await router.perform(request)
                try await sendEncrypted(.actionResult(result))
                await refreshRequested(request.controlID)
            case let .ping(nonce):
                try await sendEncrypted(.pong(nonce))
            default:
                throw RemoteProtocolError(code: .invalidFrame, message: "Message is not valid in authenticated state")
            }
        }
    }

    private func sendEncrypted(_ message: RemoteMessage) async throws {
        guard let crypto else { throw RemoteProtocolError(code: .authenticationFailed, message: "No session") }
        try await io.send(.encrypted(try crypto.seal(message)))
    }

    private static func makeCrypto(
        role: RemotePeerRole,
        privateKey: P256.KeyAgreement.PrivateKey,
        peerKey: Data,
        credential: Data,
        transcript: Data
    ) throws -> RemoteSessionCrypto {
        let keys = try RemoteSessionCrypto.deriveSessionKeys(
            role: role,
            privateKey: privateKey,
            peerPublicKey: peerKey,
            credential: credential,
            transcript: transcript
        )
        return RemoteSessionCrypto(sendKey: keys.send, receiveKey: keys.receive, noncePrefix: UInt32.random(in: .min ... .max))
    }

    private static func randomData(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max) })
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
        return difference == 0
    }
}
