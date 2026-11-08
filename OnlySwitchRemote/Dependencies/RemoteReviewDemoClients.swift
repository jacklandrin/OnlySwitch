import Foundation
import RemoteCore

extension RemoteConnectionClient {
    static func reviewDemo(runtime: RemoteReviewDemoRuntime) -> Self {
        Self(
            discover: {
                AsyncStream { continuation in
                    let task = Task {
                        for event in await runtime.discoveryEvents() { continuation.yield(event) }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            restartDiscovery: {},
            preparePairing: { discoveredMac, code, _ in
                try await runtime.preparePairing(discoveredMac: discoveredMac, code: code)
            },
            finalizePairing: { try await runtime.finalizePairing(transactionID: $0) },
            abortPairing: { await runtime.abortPairing(transactionID: $0) },
            select: { await runtime.select($0) },
            events: {
                let id = UUID()
                return AsyncStream { continuation in
                    let registration = Task { await runtime.registerEvents(id: id, continuation: continuation) }
                    continuation.onTermination = { _ in
                        registration.cancel()
                        Task {
                            await registration.value
                            await runtime.unregisterEvents(id: id)
                        }
                    }
                }
            },
            snapshot: { await runtime.connectionSnapshot() },
            adoptPairedMac: { await runtime.adopt($0) },
            forgetMac: { await runtime.forget($0) },
            subscribe: { try await runtime.subscribe($0) },
            send: { try await runtime.send($0) },
            fetchCodexUsage: { invocation in
                let snapshot = await runtime.connectionSnapshot()
                guard invocation.macID == snapshot.authenticatedMacID,
                      invocation.sessionID == snapshot.authenticatedSessionID else {
                    throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed")
                }
                return .init(
                    requestID: invocation.request.requestID,
                    result: .success(.init(
                        account: .init(email: "review@example.com", plan: "Plus"),
                        session: .init(remainingPercent: 82, resetAt: Date(timeIntervalSince1970: 1_800_003_600)),
                        weekly: .init(remainingPercent: 64, resetAt: Date(timeIntervalSince1970: 1_800_604_800)),
                        resetCredits: .available(count: 3, expiresAt: Date(timeIntervalSince1970: 1_800_086_400)),
                        creditBalance: .available(remaining: 12.5, limit: 50, unit: "credits"),
                        source: .oauth,
                        fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                        activity: invocation.request.includeLocalActivity ? .init(
                            dailyUsage: [.init(date: Date(timeIntervalSince1970: 1_800_000_000), tokenCount: 12_345)],
                            isPartial: false
                        ) : nil
                    ))
                )
            },
            fetchClaudeUsage: { invocation in
                let snapshot = await runtime.connectionSnapshot()
                guard invocation.macID == snapshot.authenticatedMacID, invocation.sessionID == snapshot.authenticatedSessionID else {
                    throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed")
                }
                return .init(requestID: invocation.request.requestID, result: .success(.init(
                    account: .init(email: "review@example.com", plan: "Pro"),
                    session: .init(remainingPercent: 75, resetAt: Date(timeIntervalSince1970: 1_800_003_600)),
                    weekly: .init(remainingPercent: 64, resetAt: Date(timeIntervalSince1970: 1_800_604_800)),
                    models: [.init(id: "seven_day_sonnet", name: "Sonnet", quota: .init(remainingPercent: 90, resetAt: nil))],
                    extraUsage: .init(isEnabled: false, used: nil, limit: nil, currency: nil, utilization: nil),
                    fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)) ))
            },
            sendSoundMixer: { await runtime.sendSoundMixer($0) },
            setSystemMonitorStreaming: { _ in },
            setSoundMixerStreaming: { await runtime.setSoundMixerStreaming($0) },
            setBrightnessStreaming: { await runtime.setBrightnessStreaming($0) },
            sendBrightness: { await runtime.sendBrightness($0) },
            setScreenshotsStreaming: { await runtime.setScreenshotsStreaming($0) },
            fetchScreenshotThumbnails: { try await runtime.screenshotThumbnails($0) },
            fetchScreenshotImage: { try await runtime.screenshotImage($0) },
            deleteScreenshots: { try await runtime.deleteScreenshots($0) },
            setForegrounded: { _ in },
            // The demo never closes its session in the background, so a transfer needs no hold.
            withBackgroundTransferHold: { try await $0() }
        )
    }
}

extension RemotePersistenceClient {
    static func reviewDemo(runtime: RemoteReviewDemoRuntime) -> Self {
        Self(
            saveAppState: { await runtime.saveAppState($0) },
            loadInitialSetupCompleted: { await runtime.appState().0 },
            saveInitialSetupCompleted: { await runtime.setInitialSetupCompleted($0) },
            loadPairedMacs: { await runtime.appState().1 },
            savePairedMacs: { await runtime.setPairedMacs($0) },
            upsertPairedMac: { await runtime.upsert($0) },
            updateRequiresPairing: { await runtime.updateRequiresPairing($0, value: $1) },
            updateEndpoint: { await runtime.updateEndpoint($0, description: $1, connectedAt: $2) },
            removePairedMac: { await runtime.removePairedMac($0) },
            loadSelectedMacID: { await runtime.appState().2 },
            saveSelectedMacID: { await runtime.setSelectedMacID($0) },
            loadLayout: { await runtime.layout(for: $0) },
            saveLayout: { await runtime.setLayout($0) },
            loadSystemMonitorLayout: { await runtime.systemMonitorLayout(for: $0) },
            saveSystemMonitorLayout: { await runtime.setSystemMonitorLayout($0) },
            loadCatalog: { await runtime.catalog(for: $0) },
            saveCatalog: { await runtime.setCatalog(.init(revision: $1, controls: $2), for: $0) },
            loadStatuses: { await runtime.statuses(for: $0) },
            saveStatuses: { await runtime.setStatuses($1, for: $0) },
            replaceStatusSnapshot: { await runtime.setStatuses($1, for: $0) },
            mergeStatus: { await runtime.mergeStatus($1, for: $0) },
            loadAphroditeLibrary: { _ in nil },
            replaceAphroditeLibrary: { _, _ in },
            markMacTombstoned: { await runtime.markTombstoned($0) },
            preparePairingState: { await runtime.preparePairingState($0, transactionID: $1, credentialVerifier: $2) },
            loadPreparedPairingState: { await runtime.loadPreparedPairingState() },
            adoptPreparedPairingState: { try await runtime.adoptPreparedPairingState($0) },
            finalizePairingState: { try await runtime.finalizePairingState($0) },
            restorePairingState: { await runtime.restorePairingState($0) },
            commitPairing: { _ = await runtime.commitPairingAndSelect($0) },
            commitPairingAndSelect: { await runtime.commitPairingAndSelect($0) },
            restorePairingSnapshot: { await runtime.restorePairingSnapshot(macID: $0, snapshot: $1) },
            isMacTombstoned: { await runtime.isTombstoned($0) },
            forgetMac: { await runtime.forget($0) }
        )
    }
}

extension RemoteScreenshotCacheClient {
    /// The review demo's own cache in the temporary directory, apart from `Caches/OnlyRemote/Screenshots`.
    static var reviewDemo: Self {
        live(root: FileManager.default.temporaryDirectory.appendingPathComponent("OnlyRemoteReviewDemo/Screenshots", isDirectory: true))
    }
}

extension RemoteScreenshotImageClient {
    /// Loads demo originals through the demo connection into the demo cache, never the live ones.
    static func reviewDemo(connection: RemoteConnectionClient, cache: RemoteScreenshotCacheClient) -> Self {
        .live(
            cache: cache,
            fetchImage: { try await connection.fetchScreenshotImage($0) },
            holdTransfer: { try await connection.withBackgroundTransferHold($0) },
            makeRequestID: { UUID() }
        )
    }
}
