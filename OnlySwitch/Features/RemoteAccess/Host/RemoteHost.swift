import Foundation
import Network
import RemoteCore
import RemoteTransport
import SystemMonitor

actor RemoteHost {
    @MainActor static let shared = RemoteHost(
        credentialStore: .live(),
        catalogProvider: .live,
        router: .live
    )

    let credentialStore: RemoteCredentialStore
    private let catalogProvider: RemoteCatalogProvider
    private let router: RemoteCommandRouter
    private let fixedPairingCode: String?
    private let peerDeadlines: RemotePeerDeadlines
    private let listenerFactory: @Sendable (NWEndpoint.Port) throws -> NWListener
    private let installationIDProvider: @Sendable () async throws -> UUID
    private let revocationPrepared: @Sendable () async -> Void
    private let authenticationResultSender: RemotePeerSession.AuthenticationResultSender
    let commitStageReached: @Sendable (RemotePairingCommitStage) async -> Void
    let authenticatedSessionObserver: @Sendable () -> Void
    private let systemMonitorSnapshots: @Sendable () -> AsyncThrowingStream<SystemMonitorSnapshot, Error>
    private let soundMixerSnapshots: @Sendable () -> AsyncThrowingStream<RemoteSoundMixerSnapshot, Error>
    private let soundMixerCommand: @Sendable (RemoteSoundMixerCommand) async throws -> RemoteSoundMixerSnapshot
    private let brightnessSnapshots: @Sendable (UUID) -> AsyncStream<RemoteBrightnessSnapshot>
    private let brightnessCommand: @Sendable (RemoteBrightnessCommand) async throws -> RemoteBrightnessSnapshot
    /// nil resolves `RemoteScreenshotsService.live` on the main actor when the listener starts.
    private let screenshots: RemoteScreenshotsService?
    private var resolvedScreenshots: RemoteScreenshotsService?
    private let claudeUsage: @Sendable () async -> Result<RemoteClaudeUsageSnapshot, RemoteProtocolError>
    private let codexUsage: @Sendable (Bool) async -> Result<RemoteCodexUsageSnapshot, RemoteProtocolError>
    private var eventContinuations: [
        UUID: AsyncStream<RemoteHostEvent>.Continuation
    ] = [:]
    private var currentStatus: HostStatus = .stopped
    private var listener: NWListener?
    private var configuration: RemoteHostConfiguration?
    var pairing: PairingWindow?
    var pairingFailures = 0
    var sessions: [UUID: RemotePeerSession] = [:]
    var lifecycle = RemoteHostLifecycle()
    let statusScheduler: RemoteStatusScheduler
    let catalogMonitor: RemoteCatalogMonitor
    private var catalogMonitorTask: Task<Void, Never>?

    init(
        credentialStore: RemoteCredentialStore,
        catalogProvider: RemoteCatalogProvider,
        router: RemoteCommandRouter,
        fixedPairingCode: String? = nil,
        peerDeadlines: RemotePeerDeadlines = .init(),
        listenerFactory: @escaping @Sendable (NWEndpoint.Port) throws -> NWListener = {
            try NWListener(using: .tcp, on: $0)
        },
        installationIDProvider: (@Sendable () async throws -> UUID)? = nil,
        revocationPrepared: @escaping @Sendable () async -> Void = {},
        authenticationResultSender: @escaping RemotePeerSession.AuthenticationResultSender = { operation in
            try await operation()
        },
        commitStageReached: @escaping @Sendable (RemotePairingCommitStage) async -> Void = { _ in },
        authenticatedSessionObserver: @escaping @Sendable () -> Void = {},
        systemMonitorSnapshots: @escaping @Sendable () -> AsyncThrowingStream<SystemMonitorSnapshot, Error> = {
            MacSystemMonitorCollector.liveClient().snapshots()
        },
        soundMixerSnapshots: @escaping @Sendable () -> AsyncThrowingStream<RemoteSoundMixerSnapshot, Error> = {
            AsyncThrowingStream { continuation in
                let task = Task { @MainActor in
                    do {
                        for try await snapshot in SoundMixerVM.shared.remoteSnapshots() {
                            continuation.yield(snapshot)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        },
        soundMixerCommand: @escaping @Sendable (RemoteSoundMixerCommand) async throws -> RemoteSoundMixerSnapshot = { command in
            try await SoundMixerVM.shared.performRemoteCommand(command)
        },
        brightnessSnapshots: @escaping @Sendable (UUID) -> AsyncStream<RemoteBrightnessSnapshot> = { hostID in
            AsyncStream { continuation in
                let task = Task { @MainActor in
                    for await snapshot in RemoteBrightnessProvider.shared.snapshots(hostID: hostID) {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        },
        brightnessCommand: @escaping @Sendable (RemoteBrightnessCommand) async throws -> RemoteBrightnessSnapshot = { command in
            try await MainActor.run { try RemoteBrightnessProvider.shared.perform(command) }
        },
        screenshots: RemoteScreenshotsService? = nil,
        codexUsage: @escaping @Sendable (Bool) async -> Result<RemoteCodexUsageSnapshot, RemoteProtocolError> = RemoteCodexUsageProvider.live.fetch,
        claudeUsage: @escaping @Sendable () async -> Result<RemoteClaudeUsageSnapshot, RemoteProtocolError> = RemoteClaudeUsageProvider.live.fetch
    ) {
        self.credentialStore = credentialStore
        self.catalogProvider = catalogProvider
        self.router = router
        self.fixedPairingCode = fixedPairingCode
        self.peerDeadlines = peerDeadlines
        self.listenerFactory = listenerFactory
        self.installationIDProvider = installationIDProvider ?? {
            try await credentialStore.installationID()
        }
        self.revocationPrepared = revocationPrepared
        self.authenticationResultSender = authenticationResultSender
        self.commitStageReached = commitStageReached
        self.authenticatedSessionObserver = authenticatedSessionObserver
        self.systemMonitorSnapshots = systemMonitorSnapshots
        self.soundMixerSnapshots = soundMixerSnapshots
        self.soundMixerCommand = soundMixerCommand
        self.brightnessSnapshots = brightnessSnapshots
        self.brightnessCommand = brightnessCommand
        self.screenshots = screenshots
        self.codexUsage = codexUsage
        self.claudeUsage = claudeUsage
        self.statusScheduler = RemoteStatusScheduler(provider: catalogProvider)
        self.catalogMonitor = RemoteCatalogMonitor(provider: catalogProvider)
    }

    deinit {
        for continuation in eventContinuations.values {
            continuation.finish()
        }
    }

    func start(configuration: RemoteHostConfiguration) async throws {
        _ = try await startListener(configuration: configuration, advertise: true)
    }

    func startForTesting(port: UInt16) async throws -> NWEndpoint {
        let configuration = RemoteHostConfiguration(displayName: "OnlySwitch Test", port: port)
        let endpoint = try await startListener(configuration: configuration, advertise: false)
        pairing = PairingWindow(code: fixedPairingCode ?? PairingCode.generate(), expiresAt: Date().addingTimeInterval(300))
        pairingFailures = 0
        publish(.pairingChanged(pairing))
        return endpoint
    }

    func events() -> AsyncStream<RemoteHostEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: RemoteHostEvent.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeEventContinuation(id: id) }
        }
        eventContinuations[id] = continuation
        continuation.yield(.statusChanged(currentStatus))
        return stream
    }

    func stop() async {
        let sessionIDs = lifecycle.stop()
        listener?.cancel()
        listener = nil
        if pairing != nil { cancelPairing() }
        let peers = sessionIDs.compactMap { sessions[$0] }
        sessions.removeAll()
        configuration = nil
        publish(.connectionCountChanged(0))
        publish(.statusChanged(.stopped))
        for peer in peers { await peer.close() }
        await statusScheduler.stop()
        let activeCatalogMonitorTask = catalogMonitorTask
        activeCatalogMonitorTask?.cancel()
        catalogMonitorTask = nil
        await activeCatalogMonitorTask?.value
        await catalogMonitor.stop()
    }

    func startPairing(expiresAt: Date = Date().addingTimeInterval(300)) -> PairingWindow {
        let window = PairingWindow(
            code: fixedPairingCode ?? PairingCode.generate(),
            expiresAt: expiresAt
        )
        pairing = window
        pairingFailures = 0
        publish(.pairingChanged(window))
        return window
    }

    func cancelPairing() {
        pairing = nil
        pairingFailures = 0
        publish(.pairingChanged(nil))
    }

    func revoke(deviceID: UUID) async throws {
        let credential = try await credentialStore.prepareAndDeleteForRevocation(deviceID)
        if credential != nil {
            await revocationPrepared()
        }
        let affected = lifecycle.revoke(deviceID: deviceID)
        let peers = Dictionary(uniqueKeysWithValues: affected.compactMap { id in
            sessions.removeValue(forKey: id).map { (id, $0) }
        })
        publish(.connectionCountChanged(lifecycle.authenticatedCount))
        await catalogMonitor.setAuthenticatedSessionCount(lifecycle.authenticatedCount)
        let scheduler = statusScheduler
        let store = credentialStore
        try await Self.performRevocationCleanup(
            sessionIDs: affected,
            removeSubscription: { id in await scheduler.remove(sessionID: id) },
            closePeer: { id in await peers[id]?.revoke() },
            deleteCredential: {
                if let credential { try await store.delete(deviceID, matchingCredential: credential) }
            }
        )
        publish(.devicesChanged(try await credentialStore.loadAll()))
    }

    static func performRevocationCleanup(
        sessionIDs: [UUID],
        removeSubscription: @escaping @Sendable (UUID) async -> Void,
        closePeer: @escaping @Sendable (UUID) async -> Void,
        deleteCredential: @escaping @Sendable () async throws -> Void
    ) async throws {
        for id in sessionIDs { await removeSubscription(id) }
        for id in sessionIDs { await closePeer(id) }
        try await deleteCredential()
    }

    func pairedDevices() async throws -> [PairedRemoteDevice] {
        try await credentialStore.loadAll()
    }

    private func startListener(
        configuration: RemoteHostConfiguration,
        advertise: Bool
    ) async throws -> NWEndpoint {
        if listener != nil { await stop() }
        await resolveScreenshotsIfNeeded()
        startCatalogObservationIfNeeded()
        let generation = lifecycle.beginStart()
        publish(.statusChanged(.starting))
        do {
            // Keychain failures must surface as a failed status; otherwise the host silently never advertises.
            try await credentialStore.recoverExpiredTransactions()
            let port = configuration.port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: configuration.port)!
            let listener = try listenerFactory(port)
            self.listener = listener
            self.configuration = configuration
            let macID = try await installationIDProvider()
            if advertise {
                let txt = NWTXTRecord([
                    "id": macID.uuidString,
                    "version": String(RemoteProtocolVersion.current.major),
                    "minor": String(RemoteProtocolVersion.current.minor)
                ])
                listener.service = NWListener.Service(
                    name: configuration.displayName,
                    type: configuration.serviceType,
                    txtRecord: txt
                )
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task {
                    await self?.accept(
                        connection,
                        macID: macID,
                        name: configuration.displayName,
                        generation: generation
                    )
                }
            }
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                    let gate = HostContinuationGate(continuation)
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready: gate.resume(returning: ())
                        case let .failed(error):
                            gate.resume(throwing: error)
                            Task { await self.listenerFailed(generation: generation) }
                        case .cancelled: gate.resume(throwing: CancellationError())
                        default: break
                        }
                    }
                    listener.start(queue: .global(qos: .userInitiated))
                }
            } onCancel: {
                listener.cancel()
            }
            guard self.listener === listener, lifecycle.markListening(generation: generation) else {
                listener.cancel()
                if self.listener === listener {
                    self.listener = nil
                    self.configuration = nil
                }
                throw CancellationError()
            }
            guard let boundPort = listener.port else {
                throw RemoteProtocolError(code: .invalidFrame, message: "Listener did not bind")
            }
            publish(.statusChanged(.listening(port: boundPort.rawValue)))
            return .hostPort(host: .ipv4(.loopback), port: boundPort)
        } catch {
            await listenerFailed(generation: generation)
            throw error
        }
    }

    /// The live service reads the main-actor Screenshots store, so it is built lazily rather than when
    /// `shared` is first touched.
    private func resolveScreenshotsIfNeeded() async {
        guard resolvedScreenshots == nil else { return }
        if let screenshots {
            resolvedScreenshots = screenshots
            return
        }
        let live = await MainActor.run { RemoteScreenshotsService.live }
        resolvedScreenshots = resolvedScreenshots ?? live
    }

    func publish(_ event: RemoteHostEvent) {
        if case let .statusChanged(status) = event {
            currentStatus = status
        }
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func removeEventContinuation(id: UUID) {
        eventContinuations[id] = nil
    }

    private func accept(_ connection: NWConnection, macID: UUID, name: String, generation: UInt64) {
        let sessionID = UUID()
        guard lifecycle.acceptPending(sessionID: sessionID, generation: generation) else {
            connection.cancel()
            return
        }
        let peer = RemotePeerSession(
            id: sessionID,
            connection: connection,
            macID: macID,
            macName: name,
            credentialStore: credentialStore,
            catalogSnapshot: { [catalogMonitor] in try await catalogMonitor.current() },
            router: router,
            pairingWindow: { [weak self] in await self?.activePairingWindow() },
            pairingFailed: { [weak self] in await self?.recordPairingFailure() },
            consumePairing: { [weak self] code in await self?.consumePairing(code: code) ?? false },
            pairingEpoch: { [weak self] deviceID in
                await self?.lifecycle.pairingEpoch(for: deviceID) ?? 0
            },
            pairingSnapshot: { [weak self] deviceID in
                await self?.pairingSnapshot(deviceID: deviceID, generation: generation)
            },
            validatePairing: { [weak self] snapshot in
                await self?.validatePairing(snapshot) ?? false
            },
            commitPairing: { [weak self] snapshot in
                guard let self else { return false }
                return await self.commitPairing(snapshot)
            },
            rollbackPairing: { [weak self] snapshot in
                guard let self else { return false }
                return await self.rollbackPairing(snapshot)
            },
            subscriptionsChanged: { [weak self] id, ids, sink in
                guard let self else { throw CancellationError() }
                try await self.statusScheduler.update(
                    sessionID: id,
                    ids: ids,
                    sink: sink,
                    onFailure: { [weak self] in await self?.evictSession(id) }
                )
            },
            refreshRequested: { [weak self] id in
                await self?.statusScheduler.refresh(id)
            },
            authenticated: { [weak self] sessionID, deviceID in
                await self?.sessionAuthenticated(
                    sessionID,
                    deviceID: deviceID,
                    generation: generation
                ) ?? false
            },
            authenticationAuthorized: { [weak self] sessionID, deviceID in
                await self?.sessionAuthenticationIsAuthorized(
                    sessionID,
                    deviceID: deviceID,
                    generation: generation
                ) ?? false
            },
            authenticationConfirmed: { [weak self] sessionID, deviceID in
                await self?.sessionAuthenticationConfirmed(
                    sessionID,
                    deviceID: deviceID,
                    generation: generation
                ) ?? false
            },
            systemMonitorSnapshots: systemMonitorSnapshots,
            soundMixerSnapshots: soundMixerSnapshots,
            soundMixerCommand: soundMixerCommand,
            brightnessSnapshots: brightnessSnapshots,
            brightnessCommand: brightnessCommand,
            screenshots: resolvedScreenshots ?? .unavailable,
            codexUsage: codexUsage,
            claudeUsage: claudeUsage,
            authenticationResultSender: authenticationResultSender,
            commitStageReached: commitStageReached,
            ended: { [weak self] id in await self?.sessionEnded(id) },
            deadlines: peerDeadlines
        )
        sessions[sessionID] = peer
        Task { await peer.run() }
    }

    private func listenerFailed(generation: UInt64) async {
        guard lifecycle.isActive(generation: generation) else { return }
        let sessionIDs = lifecycle.fail(generation: generation)
        let peers = sessionIDs.compactMap { sessions.removeValue(forKey: $0) }
        listener?.cancel()
        listener = nil
        configuration = nil
        if pairing != nil { cancelPairing() }
        publish(.connectionCountChanged(0))
        publish(.statusChanged(.failed("Remote access could not start")))
        for peer in peers { await peer.close() }
        await statusScheduler.stop()
        await catalogMonitor.setAuthenticatedSessionCount(0)
    }

    private func startCatalogObservationIfNeeded() {
        guard catalogMonitorTask == nil else { return }
        let changes = catalogMonitor.changes
        catalogMonitorTask = Task { [weak self] in
            for await snapshot in changes {
                guard Task.isCancelled == false else { return }
                await self?.broadcastCatalogChange(snapshot.revision)
            }
        }
    }

    private func broadcastCatalogChange(_ revision: UInt64) async {
        for (id, peer) in Array(sessions) {
            do {
                try await peer.catalogDidChange(revision: revision)
            } catch {
                await evictSession(id)
            }
        }
    }

    var hasOwnedListener: Bool { listener != nil }

}
