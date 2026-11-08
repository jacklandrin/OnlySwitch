import CryptoKit
import Foundation
import RemoteCore
import RemoteTransport

extension RemotePeerSession {
    func completePairing(
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
        advertisedCatalogRevision = catalog.revision
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

    func authenticateProvisionalReconnect(
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
            advertisedCatalogRevision = catalog.revision
            return true
        }
        return false
    }

    func handleProvisional(_ message: RemoteMessage) async throws {
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
            try await requireCommitting(committed.id, transactionID: command.transactionID)
            guard await authenticationAuthorized(id, committed.id) else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Credential was revoked")
            }
            try await requireCommitting(committed.id, transactionID: command.transactionID)
            try await sendEncrypted(.pairingCommitted(command))
        }
        try requireCommitting(committed.id, transactionID: command.transactionID)
        guard await authenticationConfirmed(id, committed.id) else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Credential was revoked")
        }
        try requireCommitting(committed.id, transactionID: command.transactionID)
        let currentCatalog = try await catalogSnapshot()
        try requireCommitting(committed.id, transactionID: command.transactionID)
        try await sendCatalogChangeIfNeeded(currentCatalog)
        try requireCommitting(committed.id, transactionID: command.transactionID)
        try? await credentialStore.finalizeRepair(
            deviceID: committed.id,
            matchingCredential: committed.credential
        )
        try requireCommitting(committed.id, transactionID: command.transactionID)
        authenticatedCredential = committed.credential
        state = .authenticated(committed.id)
        startAphroditeChangeObservation()

        // A monitor refresh can be skipped while this peer is still committing.
        // Re-read after the synchronous state transition so every revision is
        // either observed here or by the normal authenticated broadcast path.
        let authenticatedCatalog = try await catalogSnapshot()
        try await sendCatalogChangeIfNeeded(authenticatedCatalog)
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
}
