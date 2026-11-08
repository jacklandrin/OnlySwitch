import Foundation
import RemoteCore

extension RemoteConnectionRuntime {
    func preparePairing(_ mac: DiscoveredMac, code: String, deviceName: String) async throws -> PreparedPairing {
        guard mac.protocolVersion.isCompatible(with: .current),
              mac.protocolVersion.supportsTransactionalPairing else {
            throw RemoteProtocolError(code: .upgradeRequired, message: "Update OnlySwitch on this Mac to pair")
        }
        let cleanName = try Self.validatedDeviceName(deviceName)
        await abortPairing(nil)
        guard pairingToken == nil,
              preparingSession == nil,
              pendingPreparedSession == nil else {
            throw RemoteProtocolError(
                code: .authenticationFailed,
                message: "Previous pairing rollback is incomplete"
            )
        }
        guard foregrounded else { throw CancellationError() }
        let deviceID = self.deviceID
        let pairingToken = UUID()
        self.pairingToken = pairingToken
        let newSessionToken = UUID()
        let task = Task {
            try await Self.withTimeout(.seconds(15)) {
                try await RemoteClientSession.preparePairing(
                    endpoint: mac.endpoint,
                    expectedMacID: mac.id,
                    code: code.uppercased(),
                    deviceID: deviceID,
                    deviceName: cleanName,
                    sessionToken: newSessionToken,
                    event: { [weak self] message in
                        await self?.handle(message, macID: mac.id, sessionToken: newSessionToken)
                    },
                    disconnected: { [weak self] error in
                        await self?.sessionDisconnected(macID: mac.id, sessionToken: newSessionToken, error: error)
                    }
                )
            }
        }
        pairingTask = task
        let result: RemoteClientSession.PairingResult
        do {
            result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
                Task { await self.abortPairing(token: pairingToken) }
            }
        } catch {
            await abortPairing(token: pairingToken)
            throw error
        }
        guard result.credential.count == 32 else {
            await result.session.close()
            await abortPairing(token: pairingToken)
            throw RemoteKeychainClient.Error.invalidCredentialLength
        }
        guard self.pairingToken == pairingToken, foregrounded, Task.isCancelled == false else {
            await result.session.close()
            throw CancellationError()
        }
        preparingSession = .init(
            session: result.session,
            pairingToken: pairingToken,
            transactionID: result.transactionID
        )
        let value = PairedMac(
            id: mac.id,
            displayName: mac.displayName,
            lastEndpointDescription: String(describing: mac.endpoint),
            lastConnectedAt: .now,
            requiresPairing: false
        )
        let catalog: RemoteCatalogCache
        do { catalog = try await Self.withTimeout(.seconds(10)) { try await result.session.receiveCatalog() } }
        catch {
            if self.pairingToken == pairingToken {
                preparingSession = nil
                self.pairingToken = nil
                await result.session.abortPairing(result.transactionID)
                await closeSession(result.session)
                throw error
            }
            throw CancellationError()
        }
        do {
            try Self.validateCatalog(catalog, minimumRevision: result.catalogRevision)
        } catch {
            if self.pairingToken == pairingToken {
                preparingSession = nil
                self.pairingToken = nil
                await result.session.abortPairing(result.transactionID)
                await closeSession(result.session)
                throw error
            }
            throw CancellationError()
        }
        guard self.pairingToken == pairingToken, foregrounded, Task.isCancelled == false else {
            if self.pairingToken == pairingToken {
                preparingSession = nil
                self.pairingToken = nil
                await result.session.abortPairing(result.transactionID)
                await closeSession(result.session)
            }
            throw CancellationError()
        }
        let persistenceRecord: PreparedPairingPersistenceRecord
        let credentialVerifier = RemoteKeychainClient.credentialVerifier(result.credential)
        do {
            persistenceRecord = try await localStateMutations.run { [keychain, persistence] in
                try await keychain.saveProvisionalCredential(result.transactionID, result.credential)
                do {
                    return try await persistence.preparePairingState(value, result.transactionID, credentialVerifier)
                } catch {
                    _ = try? await keychain.deleteProvisionalCredential(result.transactionID, credentialVerifier)
                    throw error
                }
            }
        } catch {
            guard self.pairingToken == pairingToken else { throw CancellationError() }
            pairingTask = nil
            preparingSession = nil
            self.pairingToken = nil
            await result.session.abortPairing(result.transactionID)
            await closeSession(result.session)
            throw error
        }
        pairingTask = nil
        preparingSession = nil
        pendingPreparedSession = PendingPreparedSession(
            session: result.session, candidateSessionNeedsClose: true,
            sessionToken: newSessionToken, pairingToken: pairingToken,
            generation: generation, macID: mac.id, transactionID: result.transactionID,
            mac: value, catalog: catalog, candidateCredential: result.credential,
            persistenceRecord: persistenceRecord,
            endpoint: mac.endpoint, deviceName: cleanName
        )
        await pairingDurableCommitCompleted()
        guard self.pairingToken == pairingToken,
              pendingPreparedSession?.transactionID == result.transactionID,
              foregrounded,
              Task.isCancelled == false else {
            if self.pairingToken == pairingToken {
                await abortPairing(token: pairingToken, transactionID: result.transactionID)
            }
            throw CancellationError()
        }
        return PreparedPairing(transactionID: result.transactionID, mac: value, catalog: catalog)
    }

    func finalizePairing(_ transactionID: UUID) async throws -> PairedMac {
        guard var pending = pendingPreparedSession, pending.transactionID == transactionID else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing transaction is unavailable")
        }
        guard finalizingTransactionID == nil || finalizingTransactionID == transactionID else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Another pairing transaction is finalizing")
        }
        finalizingTransactionID = transactionID
        try await persistence.adoptPreparedPairingState(transactionID)
        var state: PairingTransactionState
        do {
            let committingSession = pending.session
            state = try await Self.withTimeout(.seconds(10)) { try await committingSession.commitPairing(transactionID) }
        } catch {
            do {
                let provisionalSession = pending.session
                state = try await Self.withTimeout(.seconds(10)) {
                    try await provisionalSession.resolvePairing(transactionID)
                }
            } catch {
                let recoveryPending = pending
                let recovery = try await RemoteClientSession.authenticate(
                    endpoint: recoveryPending.endpoint, expectedMacID: recoveryPending.macID,
                    credential: recoveryPending.candidateCredential, deviceID: deviceID,
                    deviceName: recoveryPending.deviceName, sessionToken: recoveryPending.sessionToken,
                    event: { [weak self] message in
                        await self?.handle(message, macID: recoveryPending.macID, sessionToken: recoveryPending.sessionToken)
                    },
                    disconnected: { [weak self] error in
                        await self?.sessionDisconnected(macID: recoveryPending.macID, sessionToken: recoveryPending.sessionToken, error: error)
                    }
                )
                await pending.session.close()
                pending = PendingPreparedSession(
                    session: recovery, candidateSessionNeedsClose: true,
                    sessionToken: pending.sessionToken, pairingToken: pending.pairingToken,
                    generation: pending.generation, macID: pending.macID, transactionID: pending.transactionID,
                    mac: pending.mac, catalog: pending.catalog, candidateCredential: pending.candidateCredential,
                    persistenceRecord: pending.persistenceRecord,
                    endpoint: pending.endpoint, deviceName: pending.deviceName
                )
                pendingPreparedSession = pending
                state = try await Self.withTimeout(.seconds(10)) { try await recovery.resolvePairing(transactionID) }
            }
        }
        guard state == .committed else {
            if state == .aborted {
                finalizingTransactionID = nil
                await abortPairing(transactionID)
            }
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing was not committed")
        }
        let committedPending = pending
        try await localStateMutations.run { [keychain, persistence] in
            guard try await keychain.promoteProvisionalCredential(
                transactionID,
                committedPending.macID,
                committedPending.persistenceRecord.candidateCredentialVerifier
            ) else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing credential ownership changed")
            }
            try await persistence.finalizePairingState(transactionID)
        }
        guard pendingPreparedSession?.transactionID == transactionID else { throw CancellationError() }
        generation &+= 1
        connectionTask?.cancel()
        connectionTask = nil
        aphroditeTransfers.removeAll()
        let previousSession = session
        session = pending.session
        sessionToken = pending.sessionToken
        selected = pending.mac
        pairingToken = nil
        pendingPreparedSession = nil
        eventHub.yield(.sessionStarted(pending.macID, pending.sessionToken))
        eventHub.yield(.authenticated(pending.macID))
        eventHub.yield(.catalog(pending.macID, pending.catalog.revision, pending.catalog.controls))
        try? await persistence.saveCatalog(pending.macID, pending.catalog.revision, pending.catalog.controls)
        pending.session.startReceiving()
        try? await pending.session.requestAphroditeLibraryIfSupported()
        if let previousSession {
            try? await previousSession.setSystemMonitorStreaming(false)
            await closeSession(previousSession)
        }
        if foregrounded == false { await setForegrounded(false) }
        finalizingTransactionID = nil
        return pending.mac
    }

    func abortPairing(_ transactionID: UUID?) async {
        guard let token = pairingToken else { return }
        if let transactionID {
            let matchesPreparing = preparingSession?.transactionID == transactionID
            let matchesPrepared = pendingPreparedSession?.transactionID == transactionID
            guard matchesPreparing || matchesPrepared else { return }
        }
        await abortPairing(token: token, transactionID: transactionID)
    }

    private func abortPairing(token: UUID, transactionID: UUID? = nil) async {
        guard pairingToken == token else { return }
        if let finalizingTransactionID,
           transactionID == nil || transactionID == finalizingTransactionID { return }
        pairingTask?.cancel()
        pairingTask = nil
        if let preparing = preparingSession, preparing.pairingToken == token {
            preparingSession = nil
            await preparing.session.abortPairing(preparing.transactionID)
            await closeSession(preparing.session)
            guard pairingToken == token else { return }
        }
        guard let pending = pendingPreparedSession, pending.pairingToken == token,
              transactionID == nil || transactionID == pending.transactionID else {
            if pairingToken == token { pairingToken = nil }
            return
        }
        var rollbackPending = pending
        if rollbackPending.candidateSessionNeedsClose {
            rollbackPending.candidateSessionNeedsClose = false
            pendingPreparedSession = rollbackPending
            await rollbackPending.session.abortPairing(rollbackPending.transactionID)
            await closeSession(rollbackPending.session)
        }
        let restored = await restorePreparedPairing(rollbackPending)
        guard pairingToken == token,
              pendingPreparedSession?.transactionID == pending.transactionID else { return }
        if restored {
            pendingPreparedSession = nil
            pairingToken = nil
        }
    }

    private func restorePreparedPairing(_ pending: PendingPreparedSession) async -> Bool {
        do {
            return try await localStateMutations.run { [keychain, persistence] in
                guard try await keychain.deleteProvisionalCredential(
                    pending.transactionID,
                    pending.persistenceRecord.candidateCredentialVerifier
                ) else { return false }
                try await persistence.restorePairingState(pending.persistenceRecord)
                return true
            }
        } catch {
            return false
        }
    }
}
