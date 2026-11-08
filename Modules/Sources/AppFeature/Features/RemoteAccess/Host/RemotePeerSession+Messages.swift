import Aphrodite
import Foundation
import RemoteCore
import RemoteTransport

extension RemotePeerSession {
    func messageLoop() async throws {
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
            // The dashboard tile enables/disables the mixer after the session is already
            // authenticated. Publish its new state immediately so the iOS surface can appear
            // (or disappear) without reconnecting.
            if request.controlID.kind == .builtIn,
               request.controlID.value == "274877906944",
               negotiatedVersion?.supportsSoundMixerRemote == true {
                try await sendEncrypted(.soundMixerSnapshot(await SoundMixerVM.shared.remoteSnapshot()))
            }
        case .soundMixerSnapshotRequest:
            try requireSoundMixer()
            try await sendEncrypted(.soundMixerSnapshot(await SoundMixerVM.shared.remoteSnapshot()))
        case let .soundMixerCommand(command):
            try requireSoundMixer()
            if command.requiresSoundMixerTab { try requireSoundMixerTab() }
            guard let snapshot = try await commandSnapshot({ try await soundMixerCommand(command) }) else { return }
            try await sendEncrypted(.soundMixerSnapshot(snapshot))
        case let .soundMixerSubscriptionUpdate(enabled):
            try requireSoundMixerTab()
            if enabled {
                startSoundMixerStreaming()
            } else {
                stopSoundMixerStreaming()
            }
        case let .brightnessSubscriptionUpdate(enabled):
            try requireBrightness()
            if enabled {
                startBrightnessStreaming()
            } else {
                stopBrightnessStreaming()
            }
        case let .brightnessCommand(command):
            try requireBrightness()
            guard let snapshot = try await commandSnapshot({ try await brightnessCommand(command) }) else { return }
            try await sendEncrypted(.brightnessSnapshot(snapshot))
        case let .screenshotsSubscriptionUpdate(enabled):
            try requireScreenshots()
            if enabled {
                startScreenshotsStreaming()
            } else {
                stopScreenshotsStreaming()
            }
        case let .screenshotThumbnailsRequest(request):
            try requireScreenshots()
            guard try await acceptScreenshotRequest(request.requestID) else { return }
            enqueueScreenshotThumbnails(request)
        case let .screenshotImageRequest(request):
            try requireScreenshots()
            guard try await acceptScreenshotRequest(request.requestID) else { return }
            startScreenshotImageTransfer(request)
        case let .screenshotDeleteRequest(request):
            try requireScreenshots()
            guard try await acceptScreenshotRequest(request.requestID) else { return }
            let failed = await screenshots.delete(request.ids)
            try await sendEncrypted(.screenshotDeleteResult(.init(requestID: request.requestID, failedIDs: failed)))
        case let .systemMonitorSubscriptionUpdate(enabled):
            guard negotiatedVersion?.supportsSystemMonitorRemote == true else {
                throw RemoteProtocolError(
                    code: .actionNotSupported,
                    message: "System Monitor remote viewing requires a newer OnlySwitch"
                )
            }
            if enabled {
                startSystemMonitorStreaming()
            } else {
                stopSystemMonitorStreaming()
            }
        case let .codexUsageRequest(request):
            guard negotiatedVersion?.supportsCodexUsageRemote == true else {
                let error = RemoteProtocolError(code: .upgradeRequired, message: "Codex Usage requires a newer OnlySwitch")
                try await sendEncrypted(.codexUsageResult(.init(requestID: request.requestID, result: .failure(error))))
                return
            }
            codexUsageGeneration &+= 1
            let generation = codexUsageGeneration
            codexUsageTask?.cancel()
            codexUsageTask = Task { [weak self, codexUsage] in
                let result = await codexUsage(request.includeLocalActivity)
                guard Task.isCancelled == false else { return }
                try? await self?.finishCodexUsage(requestID: request.requestID, generation: generation, result: result)
            }
        case let .claudeUsageRequest(request):
            guard negotiatedVersion?.supportsClaudeUsageRemote == true else {
                let error = RemoteProtocolError(code: .upgradeRequired, message: "Claude Usage requires a newer OnlySwitch")
                try await sendEncrypted(.claudeUsageResult(.init(requestID: request.requestID, result: .failure(error))))
                return
            }
            claudeUsageGeneration &+= 1
            let generation = claudeUsageGeneration
            claudeUsageTask?.cancel()
            claudeUsageTask = Task { [weak self, claudeUsage] in
                let result = await claudeUsage()
                guard Task.isCancelled == false else { return }
                try? await self?.finishClaudeUsage(requestID: request.requestID, generation: generation, result: result)
            }
        case .aphroditeLibraryRequest:
            guard negotiatedVersion?.supportsAphroditeRemote == true else {
                throw RemoteProtocolError(code: .actionNotSupported, message: "Aphrodite sharing requires a newer OnlyRemote")
            }
            try await sendAphroditeSnapshotIfSupported()
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

    private func sendAphroditeSnapshotIfSupported() async throws {
        guard case .authenticated = state, negotiatedVersion?.supportsAphroditeRemote == true else { return }
        for message in try await aphroditeSnapshotMessages() {
            try Task.checkCancellation()
            try await sendEncrypted(message)
        }
    }

    func startAphroditeChangeObservation() {
        aphroditeChangesTask?.cancel()
        aphroditeChangesTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .aphroditeLibraryChanged) {
                guard Task.isCancelled == false else { return }
                try? await self?.sendAphroditeSnapshotIfSupported()
            }
        }
    }

    private func finishCodexUsage(
        requestID: UUID,
        generation: UInt64,
        result: Result<RemoteCodexUsageSnapshot, RemoteProtocolError>
    ) async throws {
        guard generation == codexUsageGeneration, case .authenticated = state else { return }
        codexUsageTask = nil
        try await sendEncrypted(.codexUsageResult(.init(requestID: requestID, result: result)))
    }

    private func finishClaudeUsage(
        requestID: UUID,
        generation: UInt64,
        result: Result<RemoteClaudeUsageSnapshot, RemoteProtocolError>
    ) async throws {
        guard generation == claudeUsageGeneration, case .authenticated = state else { return }
        claudeUsageTask = nil
        try await sendEncrypted(.claudeUsageResult(.init(requestID: requestID, result: result)))
    }

    func sendCatalog() async throws {
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
        advertisedCatalogRevision = snapshot.revision
    }
}
