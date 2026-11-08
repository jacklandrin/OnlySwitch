import Foundation
import RemoteCore

extension RemoteConnectionRuntime {
    func connectWithRetry(_ mac: PairedMac, generation expectedGeneration: UInt64) async {
        let delays: [Duration] = [.zero, .milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)]
        for delay in delays {
            guard Task.isCancelled == false, foregrounded, generation == expectedGeneration, selected?.id == mac.id else { return }
            do {
                if delay != .zero { try await Task.sleep(for: delay) }
                let candidates = Self.orderedCandidates(
                    Array((discovered[mac.id] ?? [:]).values),
                    preferredEndpointDescription: mac.lastEndpointDescription
                )
                if try await recoverPreparedPairingIfNeeded(
                    mac,
                    candidates: candidates,
                    expectedGeneration: expectedGeneration
                ) {
                    return
                }
                guard candidates.isEmpty == false else {
                    throw RemoteProtocolError(code: .requestTimedOut, message: "Mac was not found on the local network")
                }
                guard let credential = try await keychain.loadCredential(mac.id), credential.count == 32 else {
                    await markRequiresPairing(mac.id)
                    eventHub.yield(.offline(mac.id, "Pairing is required"))
                    return
                }
                eventHub.yield(.connecting(mac.id))
                let deviceID = self.deviceID
                var connectedSession: (RemoteClientSession, UUID, DiscoveredMac)?
                var candidateError: Swift.Error?
                for candidate in candidates {
                    guard Task.isCancelled == false, generation == expectedGeneration, selected?.id == mac.id, foregrounded else { return }
                    let newSessionToken = UUID()
                    do {
                        let connected = try await Self.withTimeout(.seconds(15)) {
                            try await RemoteClientSession.authenticate(
                                endpoint: candidate.endpoint,
                                expectedMacID: mac.id,
                                credential: credential,
                                deviceID: deviceID,
                                deviceName: RemoteDeviceIdentity.name,
                                sessionToken: newSessionToken,
                                event: { [weak self] message in
                                    await self?.handle(message, macID: mac.id, sessionToken: newSessionToken)
                                },
                                disconnected: { [weak self] error in
                                    await self?.sessionDisconnected(
                                        macID: mac.id,
                                        sessionToken: newSessionToken,
                                        error: error
                                    )
                                }
                            )
                        }
                        connectedSession = (connected, newSessionToken, candidate)
                        break
                    } catch is RemoteClientSession.AuthenticatedCredentialRevocation {
                        guard generation == expectedGeneration,
                              selected?.id == mac.id,
                              foregrounded else { return }
                        let revocation = beginRevocation(
                            macID: mac.id,
                            credential: credential,
                            generation: expectedGeneration,
                            authenticatedSessionToken: newSessionToken,
                            source: .offline
                        )
                        await commitRevocation(revocation)
                        return
                    } catch {
                        candidateError = error
                    }
                }
                guard let (connected, newSessionToken, authenticatedCandidate) = connectedSession else {
                    throw candidateError ?? RemoteProtocolError(code: .requestTimedOut, message: "No reachable Mac candidate")
                }
                guard generation == expectedGeneration, selected?.id == mac.id, foregrounded else {
                    await connected.close()
                    return
                }
                session = connected
                sessionToken = newSessionToken
                selected?.lastEndpointDescription = String(describing: authenticatedCandidate.endpoint)
                selected?.lastConnectedAt = .now
                try? await persistence.updateEndpoint(
                    mac.id,
                    selected?.lastEndpointDescription,
                    selected?.lastConnectedAt
                )
                eventHub.yield(.sessionStarted(mac.id, newSessionToken))
                eventHub.yield(.authenticated(mac.id))
                connected.startReceiving()
                try? await connected.requestAphroditeLibraryIfSupported()
                do {
                    try await catalogRequest(connected)
                } catch {
                    await connected.close()
                    if Self.shouldClearSession(currentToken: sessionToken, failedToken: newSessionToken) {
                        session = nil
                        sessionToken = nil
                    }
                    throw error
                }
                return
            } catch is CancellationError {
                return
            } catch {
                guard generation == expectedGeneration, selected?.id == mac.id, foregrounded else { return }
                eventHub.yield(.offline(mac.id, Self.safeMessage(error)))
            }
        }
    }

    private func recoverPreparedPairingIfNeeded(
        _ mac: PairedMac,
        candidates: [DiscoveredMac],
        expectedGeneration: UInt64
    ) async throws -> Bool {
        guard let record = try await persistence.loadPreparedPairingState(),
              record.candidate.id == mac.id else { return false }

        let provisional = try await keychain.loadProvisionalCredential(record.transactionID)
        let committed = try await keychain.loadCredential(mac.id)
        let credential = [provisional, committed]
            .compactMap { $0 }
            .first { RemoteKeychainClient.credentialVerifier($0) == record.candidateCredentialVerifier }

        guard let credential else {
            guard record.phase == .prepared else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing recovery credential is unavailable")
            }
            try await restorePersistedPreparedPairing(record)
            installPreviousSelection(from: record, expectedGeneration: expectedGeneration)
            return true
        }

        var lastError: Swift.Error?
        for candidate in candidates {
            guard generation == expectedGeneration,
                  selected?.id == mac.id,
                  foregrounded,
                  Task.isCancelled == false else { throw CancellationError() }
            let recoveryToken = UUID()
            do {
                let recovered = try await Self.withTimeout(.seconds(15)) {
                    try await RemoteClientSession.authenticate(
                        endpoint: candidate.endpoint,
                        expectedMacID: mac.id,
                        credential: credential,
                        deviceID: self.deviceID,
                        deviceName: RemoteDeviceIdentity.name,
                        sessionToken: recoveryToken,
                        event: { [weak self] message in
                            await self?.handle(message, macID: mac.id, sessionToken: recoveryToken)
                        },
                        disconnected: { [weak self] error in
                            await self?.sessionDisconnected(macID: mac.id, sessionToken: recoveryToken, error: error)
                        }
                    )
                }
                if record.phase == .prepared {
                    await recovered.abortPairing(record.transactionID)
                    await closeSession(recovered)
                    try await restorePersistedPreparedPairing(record)
                    installPreviousSelection(from: record, expectedGeneration: expectedGeneration)
                    return true
                }

                finalizingTransactionID = record.transactionID
                let state = try await Self.withTimeout(.seconds(10)) {
                    try await recovered.resolvePairing(record.transactionID)
                }
                guard state == .committed else {
                    await closeSession(recovered)
                    throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing recovery was not committed")
                }
                let catalog = try await Self.withTimeout(.seconds(10)) { try await recovered.receiveCatalog() }
                try Self.validateCatalog(catalog, minimumRevision: 0)
                try await localStateMutations.run { [keychain, persistence] in
                    guard try await keychain.promoteProvisionalCredential(
                        record.transactionID,
                        mac.id,
                        record.candidateCredentialVerifier
                    ) else {
                        throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing credential ownership changed")
                    }
                    try await persistence.finalizePairingState(record.transactionID)
                }
                guard generation == expectedGeneration,
                      selected?.id == mac.id,
                      foregrounded else {
                    await closeSession(recovered)
                    throw CancellationError()
                }
                session = recovered
                sessionToken = recoveryToken
                selected = record.candidate
                selected?.lastEndpointDescription = String(describing: candidate.endpoint)
                selected?.lastConnectedAt = .now
                eventHub.yield(.sessionStarted(mac.id, recoveryToken))
                eventHub.yield(.authenticated(mac.id))
                eventHub.yield(.catalog(mac.id, catalog.revision, catalog.controls))
                try? await persistence.saveCatalog(mac.id, catalog.revision, catalog.controls)
                recovered.startReceiving()
                try? await recovered.requestAphroditeLibraryIfSupported()
                finalizingTransactionID = nil
                return true
            } catch {
                lastError = error
            }
        }
        if record.phase == .prepared {
            try await restorePersistedPreparedPairing(record)
            installPreviousSelection(from: record, expectedGeneration: expectedGeneration)
            return true
        }
        throw lastError ?? RemoteProtocolError(code: .requestTimedOut, message: "Pairing recovery Mac was unreachable")
    }

    private func restorePersistedPreparedPairing(_ record: PreparedPairingPersistenceRecord) async throws {
        try await localStateMutations.run { [keychain, persistence] in
            guard try await keychain.deleteProvisionalCredential(
                record.transactionID,
                record.candidateCredentialVerifier
            ) else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing credential ownership changed")
            }
            try await persistence.restorePairingState(record)
        }
    }

    private func installPreviousSelection(
        from record: PreparedPairingPersistenceRecord,
        expectedGeneration: UInt64
    ) {
        if generation == expectedGeneration {
            selected = record.previous.pairedMacs.first { $0.id == record.previous.selectedMacID }
        }
        eventHub.yield(.persistenceRestored)
    }

    private func replaceSession(_ newSession: RemoteClientSession, token: UUID, selectedMac: PairedMac) async {
        connectionTask?.cancel()
        connectionTask = nil
        if let session { await session.close() }
        session = newSession
        sessionToken = token
        selected = selectedMac
    }
}
