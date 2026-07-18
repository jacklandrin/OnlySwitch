import CryptoKit
import Foundation
import Network
import RemoteCore
import RemoteTransport

typealias RemoteHandshake = RemoteHandshakeCrypto

enum RemotePairingCommitStage: Equatable, Sendable {
    case afterFinalize
    case duringLifecycleCommit
    case afterLifecycleCommit
    case beforeHostAuthentication
}

struct RemotePairingTransaction: Sendable {
    let record: PairedRemoteDevice
    let previous: PairedRemoteDevice?
    let snapshot: RemotePairingSnapshot

    static func begin(
        record: PairedRemoteDevice,
        credentialStore: RemoteCredentialStore,
        pairingSnapshot: @escaping @Sendable (UUID) async -> RemotePairingSnapshot?,
        consumePairing: @escaping @Sendable () async -> Bool
    ) async throws -> Self {
        guard let snapshot = await pairingSnapshot(record.id) else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing was superseded")
        }
        let previous = try await credentialStore.load(record.id)
        guard await consumePairing() else {
            throw RemoteProtocolError(code: .pairingExpired, message: "Pairing code expired")
        }
        try await credentialStore.save(record)
        return Self(record: record, previous: previous, snapshot: snapshot)
    }

    func validate(
        _ validate: @escaping @Sendable (RemotePairingSnapshot) async -> Bool
    ) async -> Bool {
        await validate(snapshot)
    }

    func commit(
        _ commit: @escaping @Sendable (RemotePairingSnapshot) async -> Bool
    ) async -> Bool {
        await commit(snapshot)
    }

    func rollback(
        credentialStore: RemoteCredentialStore,
        rollbackPairingState: @escaping @Sendable (RemotePairingSnapshot) async -> Bool,
        currentEpoch: @escaping @Sendable (UUID) async -> UInt64
    ) async {
        let restorePrevious = await rollbackPairingState(snapshot)
        try? await credentialStore.rollbackReplacement(
            record,
            previous: previous,
            restorePrevious: restorePrevious
        )
        if restorePrevious,
           await currentEpoch(record.id) != snapshot.epoch,
           let previous {
            try? await credentialStore.delete(record.id, matchingCredential: previous.credential)
        }
    }
}


actor RemotePeerSession {
    typealias AuthenticationResultSender = @Sendable (
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws -> Void

    private struct PendingPairing: Sendable {
        let transactionID: UUID
        let record: PairedRemoteDevice
        let snapshot: RemotePairingSnapshot
        let expiresAt: Date
    }

    enum State: Sendable {
        case awaitingHello
        case awaitingPairOrAuthentication
        case provisional(UUID, UUID)
        case committing(UUID, UUID)
        case authenticated(UUID)
        case closed
    }

    let id: UUID
    private let io: RemoteConnectionIO
    private let macID: UUID
    private let macName: String
    private let credentialStore: RemoteCredentialStore
    private let catalogSnapshot: @Sendable () async throws -> RemoteCatalogSnapshot
    private let router: RemoteCommandRouter
    private let pairingWindow: @Sendable () async -> PairingWindow?
    private let pairingFailed: @Sendable () async -> Void
    private let consumePairing: @Sendable (String) async -> Bool
    private let pairingEpoch: @Sendable (UUID) async -> UInt64
    private let pairingSnapshot: @Sendable (UUID) async -> RemotePairingSnapshot?
    private let validatePairing: @Sendable (RemotePairingSnapshot) async -> Bool
    private let commitPairing: @Sendable (RemotePairingSnapshot) async -> Bool
    private let rollbackPairing: @Sendable (RemotePairingSnapshot) async -> Bool
    private let subscriptionsChanged: @Sendable (UUID, Set<RemoteControlID>, @escaping RemoteStatusScheduler.Sink) async throws -> Void
    private let refreshRequested: @Sendable (RemoteControlID) async -> Void
    private let authenticated: @Sendable (UUID, UUID) async -> Bool
    private let authenticationResultSender: AuthenticationResultSender
    private let commitStageReached: @Sendable (RemotePairingCommitStage) async -> Void
    private let ended: @Sendable (UUID) async -> Void
    private let deadlines: RemotePeerDeadlines
    private var state: State = .awaitingHello
    private var crypto: RemoteSessionCrypto?
    private var pendingPairing: PendingPairing?
    private var authenticatedCredential: Data?
    private var negotiatedVersion: RemoteProtocolVersion?

    init(
        id: UUID = UUID(),
        connection: NWConnection,
        macID: UUID,
        macName: String,
        credentialStore: RemoteCredentialStore,
        catalogSnapshot: @escaping @Sendable () async throws -> RemoteCatalogSnapshot,
        router: RemoteCommandRouter,
        pairingWindow: @escaping @Sendable () async -> PairingWindow?,
        pairingFailed: @escaping @Sendable () async -> Void,
        consumePairing: @escaping @Sendable (String) async -> Bool,
        pairingEpoch: @escaping @Sendable (UUID) async -> UInt64,
        pairingSnapshot: @escaping @Sendable (UUID) async -> RemotePairingSnapshot?,
        validatePairing: @escaping @Sendable (RemotePairingSnapshot) async -> Bool,
        commitPairing: @escaping @Sendable (RemotePairingSnapshot) async -> Bool,
        rollbackPairing: @escaping @Sendable (RemotePairingSnapshot) async -> Bool,
        subscriptionsChanged: @escaping @Sendable (UUID, Set<RemoteControlID>, @escaping RemoteStatusScheduler.Sink) async throws -> Void,
        refreshRequested: @escaping @Sendable (RemoteControlID) async -> Void,
        authenticated: @escaping @Sendable (UUID, UUID) async -> Bool,
        authenticationResultSender: @escaping AuthenticationResultSender = { operation in
            try await operation()
        },
        commitStageReached: @escaping @Sendable (RemotePairingCommitStage) async -> Void = { _ in },
        ended: @escaping @Sendable (UUID) async -> Void,
        deadlines: RemotePeerDeadlines = .init()
    ) {
        self.id = id
        self.io = RemoteConnectionIO(connection: connection)
        self.macID = macID
        self.macName = macName
        self.credentialStore = credentialStore
        self.catalogSnapshot = catalogSnapshot
        self.router = router
        self.pairingWindow = pairingWindow
        self.pairingFailed = pairingFailed
        self.consumePairing = consumePairing
        self.pairingEpoch = pairingEpoch
        self.pairingSnapshot = pairingSnapshot
        self.validatePairing = validatePairing
        self.commitPairing = commitPairing
        self.rollbackPairing = rollbackPairing
        self.subscriptionsChanged = subscriptionsChanged
        self.refreshRequested = refreshRequested
        self.authenticated = authenticated
        self.authenticationResultSender = authenticationResultSender
        self.commitStageReached = commitStageReached
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
        if RemotePairingTeardownPolicy.action(for: teardownPhase) == .preserveDurablePreparedTransaction {
            pendingPairing = nil
        } else {
            await rollbackPendingPairingIfNeeded()
        }
        state = .closed
        await io.cancel()
        await ended(id)
    }

    func close() async {
        if RemotePairingTeardownPolicy.action(for: teardownPhase) == .preserveDurablePreparedTransaction {
            pendingPairing = nil
        }
        state = .closed
        await io.cancel()
        await ended(id)
    }

    private var teardownPhase: RemotePairingTeardownPhase {
        switch state {
        case .provisional: .provisional
        case .committing: .committing
        case .authenticated: .authenticated
        case .awaitingHello, .awaitingPairOrAuthentication, .closed: .other
        }
    }

    func revoke(deadline: Duration = .seconds(2)) async {
        guard case .authenticated = state,
              negotiatedVersion?.supportsAuthenticatedRevocation == true else {
            await close()
            return
        }
        await Self.notifyRevocation(
            deadline: deadline,
            send: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.sendEncrypted(.credentialRevoked)
            },
            close: { [weak self] in await self?.close() }
        )
    }

    func sendStatus(_ status: RemoteControlStatus) async throws {
        try await sendEncrypted(.statusChanged(status))
    }

    private func handshake() async throws {
        let first = try await receiveHandshakePacket()
        guard first.kind == .plaintext, case let .clientHello(client)? = first.plaintext else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Client hello required")
        }
        guard let negotiatedVersion = client.version.negotiated(with: .current) else {
            try? await io.send(.plaintext(.sessionError(.init(
                code: .upgradeRequired,
                message: "A compatible OnlySwitch version is required"
            ))))
            throw RemoteProtocolError(code: .upgradeRequired, message: "Incompatible protocol")
        }
        self.negotiatedVersion = negotiatedVersion
        guard client.deviceName.utf8.count <= 128,
              client.deviceName.isEmpty == false,
              client.deviceName.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) == false }) else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Invalid device name")
        }
        let serverKey = P256.KeyAgreement.PrivateKey()
        let server = ServerHello(
            version: negotiatedVersion,
            macID: macID,
            macName: macName,
            ephemeralPublicKey: serverKey.publicKey.rawRepresentation,
            challenge: Self.randomData(count: 32)
        )
        try await io.send(.plaintext(.serverHello(server)))
        state = .awaitingPairOrAuthentication
        let transcript = try RemoteHandshake.transcript(client: client, server: server)
        let next = try await receiveHandshakePacket()

        if next.kind == .plaintext, next.plaintext == .pairingRequest {
            guard negotiatedVersion.supportsTransactionalPairing else {
                try? await io.send(.plaintext(.sessionError(.init(
                    code: .upgradeRequired,
                    message: "Transactional pairing requires protocol 1.2"
                ))))
                throw RemoteProtocolError(code: .upgradeRequired, message: "Transactional pairing requires protocol 1.2")
            }
            try await completePairing(
                client: client,
                serverKey: serverKey,
                transcript: transcript
            )
            return
        }

        if try await authenticateProvisionalReconnect(
            packet: next,
            client: client,
            serverKey: serverKey,
            transcript: transcript
        ) {
            return
        }

        let stored: PairedRemoteDevice
        switch try await credentialStore.authenticationRecord(client.deviceID) {
        case let .credential(record):
            stored = record
        case .revoked:
            if negotiatedVersion.supportsAuthenticatedRevocation,
               let verifier = try await credentialStore.loadRevocationVerifier(client.deviceID) {
                let proof = RemoteHandshake.revocationProof(verifier: verifier, transcript: transcript)
                try await io.send(.plaintext(.credentialRevocationProof(.init(
                    deviceID: client.deviceID,
                    proof: proof
                ))))
                throw RemoteProtocolError(code: .authenticationFailed, message: "Credential was revoked")
            }
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing required")
        case .missing:
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing required")
        }
        crypto = try Self.makeCrypto(
            role: .server,
            privateKey: serverKey,
            peerKey: client.ephemeralPublicKey,
            credential: stored.credential,
            transcript: transcript
        )
        try await authenticate(
            packet: next,
            client: client,
            credential: stored.credential,
            transcript: transcript
        )
    }

    private func completePairing(
        client: ClientHello,
        serverKey: P256.KeyAgreement.PrivateKey,
        transcript: Data
    ) async throws {
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
        guard let snapshot = await pairingSnapshot(client.deviceID) else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing was superseded")
        }
        let credential = Self.randomData(count: 32)
        let record = PairedRemoteDevice(
            id: client.deviceID,
            name: client.deviceName,
            credential: credential,
            createdAt: .now,
            lastConnectedAt: nil
        )
        let transactionID = UUID()
        let expiresAt = min(window.expiresAt, Date().addingTimeInterval(30))
        try await credentialStore.prepareReplacement(
            record,
            transactionID: transactionID,
            expiresAt: expiresAt,
            snapshot: snapshot
        )
        pendingPairing = .init(
            transactionID: transactionID,
            record: record,
            snapshot: snapshot,
            expiresAt: expiresAt
        )
        guard await consumePairing(window.code) else {
            try await credentialStore.abortPrepared(transactionID)
            pendingPairing = nil
            throw RemoteProtocolError(code: .pairingExpired, message: "Pairing code expired")
        }
        guard await validatePairing(snapshot) else {
            await rollbackPendingPairingIfNeeded()
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing was superseded")
        }

        let pairingCrypto = try Self.makeCrypto(
            role: .server,
            privateKey: serverKey,
            peerKey: client.ephemeralPublicKey,
            credential: Data(window.code.utf8),
            transcript: transcript
        )
        let catalog = try await catalogSnapshot()
        let protectedResult = try pairingCrypto.seal(.pairingPrepared(.init(
            transactionID: transactionID,
            macID: macID,
            credential: credential,
            catalogRevision: catalog.revision,
            expiresAt: expiresAt
        )))
        try await io.send(.encrypted(protectedResult))
        crypto = try Self.makeCrypto(
            role: .server,
            privateKey: serverKey,
            peerKey: client.ephemeralPublicKey,
            credential: credential,
            transcript: transcript
        )
        let authenticationPacket = try await receiveHandshakePacket()
        guard let crypto,
              authenticationPacket.kind == .encrypted,
              let frame = authenticationPacket.encrypted,
              case let .authenticationProof(proof) = try crypto.open(frame),
              proof.deviceID == client.deviceID,
              RemoteHandshake.verifyAuthenticationProof(
                proof.proof,
                credential: credential,
                transcript: transcript
              ) else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Authentication failed")
        }
        authenticatedCredential = credential
        state = .provisional(client.deviceID, transactionID)
    }

    private func authenticateProvisionalReconnect(
        packet: RemoteWirePacket,
        client: ClientHello,
        serverKey: P256.KeyAgreement.PrivateKey,
        transcript: Data
    ) async throws -> Bool {
        guard packet.kind == .encrypted, let frame = packet.encrypted else {
            return false
        }
        let contexts = try await credentialStore.preparedPairingContexts(deviceID: client.deviceID)
        for context in contexts {
            let candidateCrypto = try Self.makeCrypto(
                role: .server,
                privateKey: serverKey,
                peerKey: client.ephemeralPublicKey,
                credential: context.record.credential,
                transcript: transcript
            )
            guard case let .authenticationProof(proof) = try? candidateCrypto.open(frame),
                  proof.deviceID == client.deviceID,
                  RemoteHandshake.verifyAuthenticationProof(
                    proof.proof,
                    credential: context.record.credential,
                    transcript: transcript
                  ) else { continue }
            guard let currentSnapshot = await pairingSnapshot(client.deviceID),
                  context.snapshot.deviceID == currentSnapshot.deviceID,
                  context.snapshot.epoch == currentSnapshot.epoch,
                  context.snapshot.wasRevoked == currentSnapshot.wasRevoked,
                  await validatePairing(currentSnapshot) else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing was superseded")
            }
            crypto = candidateCrypto
            pendingPairing = PendingPairing(
                transactionID: context.transactionID,
                record: context.record,
                snapshot: currentSnapshot,
                expiresAt: context.expiresAt
            )
            authenticatedCredential = context.record.credential
            state = .provisional(client.deviceID, context.transactionID)
            let catalog = try await catalogSnapshot()
            try await sendEncrypted(.authenticationResult(.success(.init(
                sessionID: id,
                catalogRevision: catalog.revision
            ))))
            return true
        }
        return false
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
        let catalog = try await catalogSnapshot()
        let authenticationResult = RemoteMessage.authenticationResult(
            .success(.init(sessionID: id, catalogRevision: catalog.revision))
        )
        try await authenticationResultSender { [self] in
            try await sendEncrypted(authenticationResult)
        }
        authenticatedCredential = credential
        state = .authenticated(client.deviceID)
    }

    private func rollbackPendingPairingIfNeeded() async {
        guard let pendingPairing else { return }
        self.pendingPairing = nil
        try? await credentialStore.abortPrepared(pendingPairing.transactionID)
        _ = await rollbackPairing(pendingPairing.snapshot)
    }

    private func messageLoop() async throws {
        while true {
            if case .closed = state { return }
            try await receiveAndHandleMessage()
        }
    }

    private func receiveAndHandleMessage() async throws {
        let timeout: Duration
        if let pendingPairing {
            timeout = .seconds(max(0, pendingPairing.expiresAt.timeIntervalSinceNow))
        } else {
            timeout = deadlines.idle
        }
        let packet = try await Self.withTimeout(timeout) { [io] in try await io.receive() }
        guard packet.kind == .encrypted, let frame = packet.encrypted, let crypto else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Encrypted session required")
        }
        let message = try crypto.open(frame)
        switch state {
        case .provisional:
            try await handleProvisional(message)
        case .authenticated:
            try await handleAuthenticated(message)
        case .committing:
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing commit is in progress")
        case .awaitingHello, .awaitingPairOrAuthentication, .closed:
            return
        }
    }

    private func handleProvisional(_ message: RemoteMessage) async throws {
        guard let pendingPairing,
              case let .provisional(deviceID, transactionID) = state,
              deviceID == pendingPairing.record.id,
              transactionID == pendingPairing.transactionID else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing transaction is unavailable")
        }
        switch message {
        case .catalogRequest:
            try await sendCatalog()
        case let .pairingCommit(command):
            try await commitProvisional(command, pendingPairing: pendingPairing)
        case let .pairingAbort(command):
            try await validate(command, pendingPairing: pendingPairing)
            try await credentialStore.abortPrepared(command.transactionID)
            let status = try await credentialStore.transactionStatus(command.transactionID)
            try await sendEncrypted(.pairingStatus(.init(
                transactionID: command.transactionID,
                state: status
            )))
            await rollbackPendingPairingIfNeeded()
            state = .closed
        case let .pairingStatusRequest(command):
            try await validate(command, pendingPairing: pendingPairing)
            let status = try await credentialStore.transactionStatus(
                command.transactionID,
                deviceID: deviceID,
                credential: pendingPairing.record.credential
            )
            try await sendEncrypted(.pairingStatus(.init(
                transactionID: command.transactionID,
                state: status
            )))
            if status == .aborted {
                await rollbackPendingPairingIfNeeded()
                state = .closed
            }
        case let .ping(nonce):
            try await sendEncrypted(.pong(nonce))
        default:
            throw RemoteProtocolError(code: .authenticationFailed, message: "Provisional peers cannot execute controls")
        }
    }

    private func commitProvisional(
        _ command: PairingTransactionCommand,
        pendingPairing: PendingPairing
    ) async throws {
        try await validate(command, pendingPairing: pendingPairing)
        try requireProvisional(pendingPairing)
        guard await validatePairing(pendingPairing.snapshot) else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing was superseded")
        }
        try requireProvisional(pendingPairing)
        state = .committing(pendingPairing.record.id, command.transactionID)
        let committed = try await credentialStore.finalizePrepared(command.transactionID)
        do {
            try requireCommitting(committed.id, transactionID: command.transactionID)
        } catch {
            self.pendingPairing = nil
            _ = await commitPairing(pendingPairing.snapshot)
            throw error
        }
        await commitStageReached(.afterFinalize)
        do {
            try requireCommitting(committed.id, transactionID: command.transactionID)
        } catch {
            self.pendingPairing = nil
            _ = await commitPairing(pendingPairing.snapshot)
            throw error
        }
        let lifecycleCommitted = await commitPairing(pendingPairing.snapshot)
        guard lifecycleCommitted else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing was superseded")
        }
        self.pendingPairing = nil
        try requireCommitting(committed.id, transactionID: command.transactionID)
        _ = try await credentialStore.markConnected(
            deviceID: committed.id,
            credential: committed.credential,
            at: .now
        )
        try requireCommitting(committed.id, transactionID: command.transactionID)
        await commitStageReached(.beforeHostAuthentication)
        try requireCommitting(committed.id, transactionID: command.transactionID)
        guard await authenticated(id, committed.id) else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Credential was revoked")
        }
        try requireCommitting(committed.id, transactionID: command.transactionID)
        try await authenticationResultSender { [self] in
            try await sendEncrypted(.pairingCommitted(command))
        }
        try requireCommitting(committed.id, transactionID: command.transactionID)
        try? await credentialStore.finalizeRepair(
            deviceID: committed.id,
            matchingCredential: committed.credential
        )
        try requireCommitting(committed.id, transactionID: command.transactionID)
        authenticatedCredential = committed.credential
        state = .authenticated(committed.id)
    }

    private func requireProvisional(_ pendingPairing: PendingPairing) throws {
        guard case let .provisional(deviceID, transactionID) = state,
              deviceID == pendingPairing.record.id,
              transactionID == pendingPairing.transactionID else {
            throw CancellationError()
        }
    }

    private func requireCommitting(_ deviceID: UUID, transactionID: UUID) throws {
        guard case let .committing(activeDeviceID, activeTransactionID) = state,
              activeDeviceID == deviceID,
              activeTransactionID == transactionID else {
            throw CancellationError()
        }
    }

    private func validate(
        _ command: PairingTransactionCommand,
        pendingPairing: PendingPairing
    ) async throws {
        guard command.transactionID == pendingPairing.transactionID else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing transaction is unavailable")
        }
        _ = try await credentialStore.transactionStatus(
            command.transactionID,
            deviceID: pendingPairing.record.id,
            credential: pendingPairing.record.credential
        )
    }

    private func handleAuthenticated(_ message: RemoteMessage) async throws {
        guard case let .authenticated(deviceID) = state,
              let authenticatedCredential else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Authenticated session required")
        }
        switch message {
        case .catalogRequest:
            try await sendCatalog()
        case let .subscriptionUpdate(ids):
            try await subscriptionsChanged(id, ids) { [weak self] status in
                guard let self else { throw CancellationError() }
                try await self.sendStatus(status)
            }
        case let .actionRequest(request):
            let result = await router.perform(request)
            try await sendEncrypted(.actionResult(result))
            await refreshRequested(request.controlID)
        case let .pairingCommit(command):
            let status = try await credentialStore.transactionStatus(
                command.transactionID,
                deviceID: deviceID,
                credential: authenticatedCredential
            )
            guard status == .committed else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing transaction was not committed")
            }
            _ = try await credentialStore.finalizePrepared(command.transactionID)
            try await sendEncrypted(.pairingCommitted(command))
            try? await credentialStore.finalizeRepair(
                deviceID: deviceID,
                matchingCredential: authenticatedCredential
            )
        case let .pairingAbort(command):
            _ = try await credentialStore.transactionStatus(
                command.transactionID,
                deviceID: deviceID,
                credential: authenticatedCredential
            )
            try await credentialStore.abortPrepared(command.transactionID)
            let status = try await credentialStore.transactionStatus(command.transactionID)
            try await sendEncrypted(.pairingStatus(.init(
                transactionID: command.transactionID,
                state: status
            )))
        case let .pairingStatusRequest(command):
            let status = try await credentialStore.transactionStatus(
                command.transactionID,
                deviceID: deviceID,
                credential: authenticatedCredential
            )
            try await sendEncrypted(.pairingStatus(.init(
                transactionID: command.transactionID,
                state: status
            )))
        case let .ping(nonce):
            try await sendEncrypted(.pong(nonce))
        default:
            throw RemoteProtocolError(code: .invalidFrame, message: "Message is not valid in authenticated state")
        }
    }

    private func sendCatalog() async throws {
        let snapshot = try await catalogSnapshot()
        guard snapshot.controls.allSatisfy({ descriptor in
            if case let .png(data) = descriptor.icon { return data.count <= 256 * 1_024 }
            return true
        }) else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Catalog icon exceeds 256 KiB")
        }
        try await sendEncrypted(.catalogSnapshot(
            revision: snapshot.revision,
            controls: snapshot.controls
        ))
    }

    private func sendEncrypted(_ message: RemoteMessage) async throws {
        guard let crypto else { throw RemoteProtocolError(code: .authenticationFailed, message: "No session") }
        try await io.send(.encrypted(try crypto.seal(message)))
    }

    func catalogDidChange(revision: UInt64) async throws {
        guard case .authenticated = state else { return }
        try await sendEncrypted(.catalogChanged(revision: revision))
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

    static func notifyRevocation(
        deadline: Duration,
        send: @escaping @Sendable () async throws -> Void,
        close: @escaping @Sendable () async -> Void
    ) async {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await send() }
                group.addTask {
                    try await Task.sleep(for: deadline)
                    await close()
                    throw CancellationError()
                }
                _ = try await group.next()
                group.cancelAll()
            }
        } catch {
        }
        await close()
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
