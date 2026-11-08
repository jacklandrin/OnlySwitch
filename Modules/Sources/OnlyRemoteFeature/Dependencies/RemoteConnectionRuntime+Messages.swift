import Foundation
import RemoteCore

extension RemoteConnectionRuntime {
    func handle(_ message: RemoteMessage, macID: UUID, sessionToken token: UUID) async {
        guard Self.isCurrentSession(
            selectedMacID: selected?.id,
            currentToken: sessionToken,
            eventMacID: macID,
            eventToken: token
        ) else { return }
        if Self.isAuthoritativeRevocation(message) {
            let revokedSession = session
            let revokedCredential = revokedSession?.credentialIdentity
            generation &+= 1
            let revocationGeneration = generation
            connectionTask?.cancel()
            connectionTask = nil
            await abortPairing(nil)
            session = nil
            sessionToken = nil
            guard let revokedCredential else {
                if let revokedSession { await closeSession(revokedSession) }
                return
            }
            let revocation = beginRevocation(
                macID: macID,
                credential: revokedCredential,
                generation: revocationGeneration,
                authenticatedSessionToken: token,
                source: .live
            )
            let closeTask = Task { [closeSession] in
                if let revokedSession { await closeSession(revokedSession) }
            }
            await commitRevocation(revocation)
            await closeTask.value
            return
        }
        switch message {
        case let .catalogSnapshot(revision, controls):
            try? await persistence.saveCatalog(macID, revision, controls)
            eventHub.yield(.catalog(macID, revision, controls))
        case let .statusSnapshot(statuses):
            try? await persistence.replaceStatusSnapshot(macID, statuses)
            eventHub.yield(.statusSnapshot(macID, statuses))
        case let .statusChanged(status):
            try? await persistence.mergeStatus(macID, status)
            eventHub.yield(.status(macID, status))
        case let .actionResult(result):
            eventHub.yield(.action(macID, result))
        case let .soundMixerSnapshot(snapshot):
            eventHub.yield(.soundMixer(macID, snapshot))
        case let .brightnessSnapshot(snapshot):
            eventHub.yield(.brightness(macID, snapshot))
        case let .screenshotsLibrary(library):
            eventHub.yield(.screenshots(macID, library))
        case .screenshotThumbnailsResult, .screenshotImageManifest, .screenshotImageChunk,
             .screenshotDeleteResult, .screenshotRequestFailed:
            // Correlated replies are consumed by the session's RemoteScreenshotResponses.
            break
        case .screenshotsSubscriptionUpdate, .screenshotThumbnailsRequest, .screenshotImageRequest,
             .screenshotDeleteRequest:
            // iOS → Mac only.
            break
        case let .systemMonitorSnapshot(snapshot):
            eventHub.yield(.systemMonitor(macID, snapshot))
        case let .aphroditeLibraryManifest(manifest):
            let currentRevision = (try? await persistence.loadAphroditeLibrary(macID))?.revision
            guard currentRevision.map({ $0 < manifest.revision }) ?? true else { return }
            aphroditeTransfers = [manifest.transferID: .init(manifest: manifest)]
        case let .aphroditeDocumentChunk(chunk):
            guard var transfer = aphroditeTransfers[chunk.transferID] else { return }
            do {
                try transfer.append(chunk)
                aphroditeTransfers[chunk.transferID] = transfer
            } catch {
                aphroditeTransfers[chunk.transferID] = nil
            }
        case let .aphroditeTransferComplete(transferID):
            guard let transfer = aphroditeTransfers.removeValue(forKey: transferID),
                  let snapshot = try? transfer.complete() else { return }
            do {
                try await persistence.replaceAphroditeLibrary(macID, snapshot)
                eventHub.yield(.aphroditeLibraryChanged(macID, snapshot.revision))
            } catch { return }
        case let .catalogChanged(revision):
            eventHub.yield(.catalogInvalidated(macID, revision))
            guard let activeSession = session else { return }
            do {
                try await catalogRequest(activeSession)
            } catch {
                await recoverFromCatalogRefreshFailure(
                    macID: macID,
                    sessionToken: token,
                    error: error
                )
            }
        default:
            break
        }
    }

    private func recoverFromCatalogRefreshFailure(
        macID: UUID,
        sessionToken token: UUID,
        error: Swift.Error
    ) async {
        guard foregrounded,
              Self.isCurrentSession(
                  selectedMacID: selected?.id,
                  currentToken: sessionToken,
                  eventMacID: macID,
                  eventToken: token
              ),
              let failedSession = session
        else { return }
        session = nil
        sessionToken = nil
        eventHub.yield(.offline(macID, Self.safeMessage(error) ?? "Catalog refresh failed"))
        await closeSession(failedSession)
        if let selected { await select(selected) }
    }

    func sessionDisconnected(macID: UUID, sessionToken token: UUID, error: Swift.Error) async {
        guard foregrounded, Self.isCurrentSession(
            selectedMacID: selected?.id,
            currentToken: sessionToken,
            eventMacID: macID,
            eventToken: token
        ) else { return }
        aphroditeTransfers.removeAll()
        eventHub.yield(.offline(macID, Self.safeMessage(error)))
        if let selected { await select(selected) }
    }

    func markRequiresPairing(_ id: UUID) async {
        try? await persistence.updateRequiresPairing(id, true)
    }

    func beginRevocation(
        macID: UUID,
        credential: Data,
        generation: UInt64,
        authenticatedSessionToken: UUID,
        source: LocalRevocationSource
    ) -> PendingRevocation {
        let revocation = PendingRevocation(
            token: UUID(),
            authenticatedSessionToken: authenticatedSessionToken,
            generation: generation,
            macID: macID,
            credential: credential,
            source: source
        )
        pendingRevocation = revocation
        return revocation
    }

    func commitRevocation(_ revocation: PendingRevocation) async {
        let coordinator = localStateMutations
        try? await coordinator.run { [weak self] in
            await self?.applyRevocationIfCurrent(revocation)
        }
    }

    private func applyRevocationIfCurrent(_ revocation: PendingRevocation) async {
        guard pendingRevocation?.token == revocation.token,
              pendingRevocation?.authenticatedSessionToken == revocation.authenticatedSessionToken,
              generation == revocation.generation else { return }
        guard (try? await keychain.deleteCredentialIfMatches(
            revocation.macID,
            revocation.credential
        )) == true else {
            if pendingRevocation?.token == revocation.token { pendingRevocation = nil }
            return
        }
        try? await persistence.updateRequiresPairing(revocation.macID, true)
        eventHub.yield(.revoked(revocation.macID))
        if pendingRevocation?.token == revocation.token { pendingRevocation = nil }
    }

    func enqueueRevocationForTesting(
        macID: UUID,
        credential: Data,
        source: LocalRevocationSource
    ) async {
        let revocation = beginRevocation(
            macID: macID,
            credential: credential,
            generation: generation,
            authenticatedSessionToken: UUID(),
            source: source
        )
        await commitRevocation(revocation)
    }

    private nonisolated static func saveCredentialAfterRemoteCommit(
        _ id: UUID,
        credential: Data,
        keychain: RemoteKeychainClient
    ) async throws {
        var lastError: Swift.Error?
        for _ in 0..<3 {
            do {
                try await keychain.saveCredential(id, credential)
                return
            } catch {
                lastError = error
            }
        }
        guard let lastError else { throw CancellationError() }
        throw lastError
    }
}
