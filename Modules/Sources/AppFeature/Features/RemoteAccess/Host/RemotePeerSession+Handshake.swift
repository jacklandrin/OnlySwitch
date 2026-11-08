import CryptoKit
import Foundation
import RemoteCore
import RemoteTransport

extension RemotePeerSession {
    func handshake() async throws {
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
        let advertisedCatalog = try await catalogSnapshot()
        let authenticationResult = RemoteMessage.authenticationResult(
            .success(.init(sessionID: id, catalogRevision: advertisedCatalog.revision))
        )
        try await authenticationResultSender { [self] in
            try await requireAwaitingAuthentication()
            guard await authenticationAuthorized(id, client.deviceID) else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Credential was revoked")
            }
            try await requireAwaitingAuthentication()
            try await sendEncrypted(authenticationResult)
        }
        try requireAwaitingAuthentication()
        authenticatedCredential = credential
        state = .authenticated(client.deviceID)
        startAphroditeChangeObservation()
        advertisedCatalogRevision = advertisedCatalog.revision
        guard await authenticationConfirmed(id, client.deviceID) else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Credential was revoked")
        }
        let currentCatalog = try await catalogSnapshot()
        try await sendCatalogChangeIfNeeded(currentCatalog)
    }

    func rollbackPendingPairingIfNeeded() async {
        guard let pendingPairing else { return }
        self.pendingPairing = nil
        try? await credentialStore.abortPrepared(pendingPairing.transactionID)
        _ = await rollbackPairing(pendingPairing.snapshot)
    }

    private func requireAwaitingAuthentication() throws {
        guard case .awaitingPairOrAuthentication = state else {
            throw CancellationError()
        }
    }

    func validate(
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

    func receiveHandshakePacket() async throws -> RemoteWirePacket {
        try await Self.withTimeout(deadlines.stage) { [io] in try await io.receive() }
    }
}
