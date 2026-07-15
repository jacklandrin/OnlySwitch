import CryptoKit
import Foundation
import Network
import RemoteCore
import RemoteTransport

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
    private let pairingEpoch: @Sendable (UUID) async -> UInt64
    private let paired: @Sendable (UUID, UInt64) async -> Bool
    private let subscriptionsChanged: @Sendable (UUID, Set<RemoteControlID>, @escaping RemoteStatusScheduler.Sink) async throws -> Void
    private let refreshRequested: @Sendable (RemoteControlID) async -> Void
    private let authenticated: @Sendable (UUID, UUID) async -> Bool
    private let ended: @Sendable (UUID) async -> Void
    private let deadlines: RemotePeerDeadlines
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
        pairingEpoch: @escaping @Sendable (UUID) async -> UInt64,
        paired: @escaping @Sendable (UUID, UInt64) async -> Bool,
        subscriptionsChanged: @escaping @Sendable (UUID, Set<RemoteControlID>, @escaping RemoteStatusScheduler.Sink) async throws -> Void,
        refreshRequested: @escaping @Sendable (RemoteControlID) async -> Void,
        authenticated: @escaping @Sendable (UUID, UUID) async -> Bool,
        ended: @escaping @Sendable (UUID) async -> Void,
        deadlines: RemotePeerDeadlines = .init()
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
        self.pairingEpoch = pairingEpoch
        self.paired = paired
        self.subscriptionsChanged = subscriptionsChanged
        self.refreshRequested = refreshRequested
        self.authenticated = authenticated
        self.ended = ended
        self.deadlines = deadlines
    }

    func run() async {
        do {
            try await Self.withTimeout(deadlines.handshake) { [self] in
                try await io.start()
                try await handshake()
            }
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

    func sendStatus(_ status: RemoteControlStatus) async throws {
        try await sendEncrypted(.statusChanged(status))
    }

    private func handshake() async throws {
        let first = try await receiveHandshakePacket()
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
        let next = try await receiveHandshakePacket()

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
            try await authenticate(
                packet: try await receiveHandshakePacket(),
                client: client,
                credential: credential,
                transcript: transcript
            )
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
        let proofPacket = try await receiveHandshakePacket()
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
        let epoch = await pairingEpoch(client.deviceID)
        try await credentialStore.save(record)
        guard await paired(client.deviceID, epoch) else {
            try? await credentialStore.delete(client.deviceID)
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing was superseded")
        }

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
            let packet = try await Self.withTimeout(deadlines.idle) { [io] in try await io.receive() }
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
                try await subscriptionsChanged(id, ids) { [weak self] status in
                    guard let self else { throw CancellationError() }
                    try await self.sendStatus(status)
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

    private func receiveHandshakePacket() async throws -> RemoteWirePacket {
        try await Self.withTimeout(deadlines.stage) { [io] in try await io.receive() }
    }

    static func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw CancellationError()
            }
            guard let value = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return value
        }
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
