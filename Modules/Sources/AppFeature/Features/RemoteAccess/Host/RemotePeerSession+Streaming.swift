import Foundation
import RemoteCore
import RemoteTransport

extension RemotePeerSession {
    func startSystemMonitorStreaming() {
        stopSystemMonitorStreaming()
        let snapshots = systemMonitorSnapshots
        systemMonitorTask = Task { [weak self] in
            do {
                for try await snapshot in snapshots() {
                    try Task.checkCancellation()
                    guard let self else { return }
                    try await self.sendEncrypted(.systemMonitorSnapshot(snapshot))
                }
            } catch is CancellationError {
            } catch {
                // Sampling failure affects only the monitor page; controls stay connected.
            }
        }
    }

    func stopSystemMonitorStreaming() {
        systemMonitorTask?.cancel()
        systemMonitorTask = nil
    }

    /// Commands race against apps, devices, and displays disappearing on the Mac. A failed
    /// command is dropped without a reply; the active subscription stream re-syncs the peer.
    func commandSnapshot<Snapshot: Sendable>(
        _ perform: @Sendable () async throws -> Snapshot
    ) async throws -> Snapshot? {
        do {
            return try await perform()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    func requireSoundMixer() throws {
        guard negotiatedVersion?.supportsSoundMixerRemote == true else {
            throw RemoteProtocolError(code: .actionNotSupported, message: "Sound Mixer remote control requires a newer OnlySwitch")
        }
    }

    func requireSoundMixerTab() throws {
        guard negotiatedVersion?.supportsSoundMixerTabRemote == true else {
            throw RemoteProtocolError(code: .actionNotSupported, message: "Sound Mixer tab requires a newer OnlySwitch")
        }
    }

    func requireBrightness() throws {
        guard negotiatedVersion?.supportsBrightnessRemote == true else {
            throw RemoteProtocolError(code: .actionNotSupported, message: "Brightness remote control requires a newer OnlySwitch")
        }
    }

    func startSoundMixerStreaming() {
        stopSoundMixerStreaming()
        let snapshots = soundMixerSnapshots
        soundMixerTask = Task { [weak self] in
            do {
                for try await snapshot in snapshots() {
                    try Task.checkCancellation()
                    guard let self else { return }
                    try await self.sendEncrypted(.soundMixerSnapshot(snapshot))
                }
            } catch is CancellationError {
            } catch {
                // Mixer failures affect only the Sound Mixer tab; controls stay connected.
            }
        }
    }

    func stopSoundMixerStreaming() {
        soundMixerTask?.cancel()
        soundMixerTask = nil
    }

    func startBrightnessStreaming() {
        stopBrightnessStreaming()
        let snapshots = brightnessSnapshots
        let hostID = id
        brightnessTask = Task { [weak self] in
            do {
                for await snapshot in snapshots(hostID) {
                    try Task.checkCancellation()
                    guard let self else { return }
                    try await self.sendEncrypted(.brightnessSnapshot(snapshot))
                }
            } catch {
                // Send failures end only the brightness stream; the session loop handles disconnects.
            }
        }
    }

    func stopBrightnessStreaming() {
        brightnessTask?.cancel()
        brightnessTask = nil
    }

    func requireScreenshots() throws {
        guard negotiatedVersion?.supportsScreenshotsRemote == true else {
            throw RemoteProtocolError(code: .actionNotSupported, message: "Screenshots remote viewing requires a newer OnlySwitch")
        }
    }

    /// Only a subscribed session may read or trash screenshots; others get a failure reply, not a closed session.
    func acceptScreenshotRequest(_ requestID: UUID) async throws -> Bool {
        guard screenshotsLibraryTask == nil else { return true }
        try await sendEncrypted(.screenshotRequestFailed(.init(
            requestID: requestID,
            error: .init(code: .actionNotSupported, message: "Subscribe to screenshots first")
        )))
        return false
    }

    func startScreenshotsStreaming() {
        stopScreenshotsStreaming()
        let libraries = screenshots.libraries
        let includesRecordings = negotiatedVersion?.supportsScreenRecordingsRemote == true
        screenshotsLibraryTask = Task { [weak self] in
            do {
                for await library in libraries(includesRecordings) {
                    try Task.checkCancellation()
                    guard let self else { return }
                    try await self.sendEncrypted(.screenshotsLibrary(library))
                }
            } catch {
                // Send failures end only the screenshot stream; the session loop handles disconnects.
            }
        }
    }

    func enqueueScreenshotThumbnails(_ request: RemoteScreenshotThumbnailsRequest) {
        let previous = screenshotThumbnailsTask
        let thumbnails = screenshots.thumbnails
        screenshotThumbnailsTask = Task { [weak self] in
            // Cancelling the newest request cancels the whole queue behind it.
            await withTaskCancellationHandler {
                await previous?.value
            } onCancel: {
                previous?.cancel()
            }
            guard Task.isCancelled == false else { return }
            let result = await thumbnails(request.ids)
            guard Task.isCancelled == false else { return }
            try? await self?.sendEncrypted(.screenshotThumbnailsResult(.init(
                requestID: request.requestID,
                thumbnails: result.thumbnails,
                missingIDs: result.missingIDs
            )))
        }
    }

    func startScreenshotImageTransfer(_ request: RemoteScreenshotImageRequest) {
        screenshotImageTask?.cancel()
        let image = screenshots.image
        let includesRecordings = negotiatedVersion?.supportsScreenRecordingsRemote == true
        screenshotImageTask = Task { [weak self] in
            do {
                let original = try await image(request.itemID, request.revision, includesRecordings)
                let manifest = try RemoteScreenshotImageEncoder.manifest(request: request, contentType: original.contentType, data: original.data)
                try Task.checkCancellation()
                guard let self else { return }
                try await self.sendEncrypted(.screenshotImageManifest(manifest))
                // One chunk at a time so a large recording is never copied whole.
                for index in 0..<manifest.chunkCount {
                    try Task.checkCancellation()
                    try await self.sendEncrypted(.screenshotImageChunk(RemoteScreenshotImageEncoder.chunk(request: request, data: original.data, index: index)))
                }
            } catch is CancellationError {
            } catch {
                // A superseded transfer ends silently; the peer has already moved on to the newer request.
                guard Task.isCancelled == false else { return }
                let failure = error as? RemoteProtocolError
                    ?? RemoteProtocolError(code: .executionFailed, message: "The screenshot could not be sent")
                try? await self?.sendEncrypted(.screenshotRequestFailed(.init(requestID: request.requestID, error: failure)))
            }
        }
    }

    func stopScreenshotsStreaming() {
        screenshotsLibraryTask?.cancel()
        screenshotsLibraryTask = nil
        screenshotThumbnailsTask?.cancel()
        screenshotThumbnailsTask = nil
        screenshotImageTask?.cancel()
        screenshotImageTask = nil
    }

    func sendEncrypted(_ message: RemoteMessage) async throws {
        guard let crypto else { throw RemoteProtocolError(code: .authenticationFailed, message: "No session") }
        try await io.send(.encrypted(try crypto.seal(message)))
    }

    func catalogDidChange(revision: UInt64) async throws {
        guard case .authenticated = state,
              advertisedCatalogRevision.map({ revision > $0 }) ?? true else { return }
        try await sendEncrypted(.catalogChanged(revision: revision))
        advertisedCatalogRevision = revision
    }

    func sendCatalogChangeIfNeeded(_ snapshot: RemoteCatalogSnapshot) async throws {
        guard advertisedCatalogRevision.map({ snapshot.revision > $0 }) ?? true else { return }
        try await sendEncrypted(.catalogChanged(revision: snapshot.revision))
        advertisedCatalogRevision = snapshot.revision
    }
}
