import Foundation
import Network
import RemoteCore
import RemoteTransport

actor RemoteHost {
    @MainActor static let shared = RemoteHost(
        credentialStore: .live(),
        catalogProvider: .live,
        router: .live
    )

    private let credentialStore: RemoteCredentialStore
    private let catalogProvider: RemoteCatalogProvider
    private let router: RemoteCommandRouter
    private let fixedPairingCode: String?
    private let peerDeadlines: RemotePeerDeadlines
    private let listenerFactory: @Sendable (NWEndpoint.Port) throws -> NWListener
    private let installationIDProvider: @Sendable () async throws -> UUID
    private let revocationPrepared: @Sendable () async -> Void
    private let eventStream: AsyncStream<RemoteHostEvent>
    private let eventContinuation: AsyncStream<RemoteHostEvent>.Continuation
    private var listener: NWListener?
    private var configuration: RemoteHostConfiguration?
    private var pairing: PairingWindow?
    private var pairingFailures = 0
    private var sessions: [UUID: RemotePeerSession] = [:]
    private var lifecycle = RemoteHostLifecycle()
    private let statusScheduler: RemoteStatusScheduler

    nonisolated var events: AsyncStream<RemoteHostEvent> { eventStream }

    private init(
        credentialStore: RemoteCredentialStore,
        catalogProvider: RemoteCatalogProvider,
        router: RemoteCommandRouter,
        fixedPairingCode: String? = nil,
        peerDeadlines: RemotePeerDeadlines = .init(),
        listenerFactory: @escaping @Sendable (NWEndpoint.Port) throws -> NWListener = {
            try NWListener(using: .tcp, on: $0)
        },
        installationIDProvider: (@Sendable () async throws -> UUID)? = nil,
        revocationPrepared: @escaping @Sendable () async -> Void = {}
    ) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: RemoteHostEvent.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        self.eventStream = stream
        self.eventContinuation = continuation
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
        self.statusScheduler = RemoteStatusScheduler(provider: catalogProvider)
    }

    deinit {
        eventContinuation.finish()
    }

    static func testing(
        catalog: [RemoteControlDescriptor],
        router: RemoteCommandRouter,
        pairingCode: String,
        peerDeadlines: RemotePeerDeadlines = .init(),
        listenerFactory: @escaping @Sendable (NWEndpoint.Port) throws -> NWListener = {
            try NWListener(using: .tcp, on: $0)
        },
        installationIDProvider: (@Sendable () async throws -> UUID)? = nil,
        revocationPrepared: @escaping @Sendable () async -> Void = {}
    ) -> RemoteHost {
        let provider = RemoteCatalogProvider(
            catalog: { catalog },
            status: { id, revision in
                guard let descriptor = catalog.first(where: { $0.id == id }) else {
                    throw RemoteProtocolError(code: .controlNotFound, message: "Control not found")
                }
                return RemoteControlStatus(
                    id: id,
                    isAvailable: descriptor.isAvailable,
                    unavailableReason: descriptor.unavailableReason,
                    isOn: nil,
                    secondaryInformation: nil,
                    isProcessing: false,
                    revision: revision,
                    updatedAt: .now
                )
            }
        )
        return RemoteHost(
            credentialStore: .inMemory(),
            catalogProvider: provider,
            router: router,
            fixedPairingCode: pairingCode,
            peerDeadlines: peerDeadlines,
            listenerFactory: listenerFactory,
            installationIDProvider: installationIDProvider,
            revocationPrepared: revocationPrepared
        )
    }

    func start(configuration: RemoteHostConfiguration) async throws {
        _ = try await startListener(configuration: configuration, advertise: true)
    }

    func startForTesting(port: UInt16) async throws -> NWEndpoint {
        let configuration = RemoteHostConfiguration(displayName: "OnlySwitch Test", port: port)
        let endpoint = try await startListener(configuration: configuration, advertise: false)
        pairing = PairingWindow(code: fixedPairingCode ?? PairingCode.generate(), expiresAt: Date().addingTimeInterval(300))
        pairingFailures = 0
        eventContinuation.yield(.pairingChanged(pairing))
        return endpoint
    }

    func stop() async {
        let sessionIDs = lifecycle.stop()
        listener?.cancel()
        listener = nil
        if pairing != nil { cancelPairing() }
        let peers = sessionIDs.compactMap { sessions[$0] }
        sessions.removeAll()
        configuration = nil
        eventContinuation.yield(.connectionCountChanged(0))
        eventContinuation.yield(.statusChanged(.stopped))
        for peer in peers { await peer.close() }
        await statusScheduler.stop()
    }

    func startPairing(expiresAt: Date = Date().addingTimeInterval(300)) -> PairingWindow {
        let window = PairingWindow(
            code: fixedPairingCode ?? PairingCode.generate(),
            expiresAt: expiresAt
        )
        pairing = window
        pairingFailures = 0
        eventContinuation.yield(.pairingChanged(window))
        return window
    }

    func cancelPairing() {
        pairing = nil
        pairingFailures = 0
        eventContinuation.yield(.pairingChanged(nil))
    }

    func revoke(deviceID: UUID) async throws {
        let credential = try await credentialStore.load(deviceID)?.credential
        if let credential {
            _ = try await credentialStore.prepareRevocation(deviceID, matchingCredential: credential)
            await revocationPrepared()
        }
        let affected = lifecycle.revoke(deviceID: deviceID)
        let peers = Dictionary(uniqueKeysWithValues: affected.compactMap { id in
            sessions.removeValue(forKey: id).map { (id, $0) }
        })
        eventContinuation.yield(.connectionCountChanged(lifecycle.authenticatedCount))
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
        eventContinuation.yield(.devicesChanged(try await credentialStore.loadAll()))
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
        let generation = lifecycle.beginStart()
        eventContinuation.yield(.statusChanged(.starting))
        do {
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
            eventContinuation.yield(.statusChanged(.listening(port: boundPort.rawValue)))
            return .hostPort(host: .ipv4(.loopback), port: boundPort)
        } catch {
            await listenerFailed(generation: generation)
            throw error
        }
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
            catalogProvider: catalogProvider,
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
            ended: { [weak self] id in await self?.sessionEnded(id) },
            deadlines: peerDeadlines
        )
        sessions[sessionID] = peer
        Task { await peer.run() }
    }

    func activePairingWindow() -> PairingWindow? {
        guard let pairing, pairing.expiresAt > Date(), pairingFailures < 5 else {
            if self.pairing != nil {
                self.pairing = nil
                eventContinuation.yield(.pairingChanged(nil))
            }
            return nil
        }
        return pairing
    }

    private func pairingSnapshot(
        deviceID: UUID,
        generation: UInt64
    ) -> RemotePairingSnapshot? {
        lifecycle.pairingSnapshot(for: deviceID, generation: generation)
    }

    private func validatePairing(_ snapshot: RemotePairingSnapshot) -> Bool {
        lifecycle.validateRepair(snapshot)
    }

    private func commitPairing(_ snapshot: RemotePairingSnapshot) -> Bool {
        lifecycle.commitRepair(snapshot)
    }

    private func rollbackPairing(_ snapshot: RemotePairingSnapshot) -> Bool {
        lifecycle.rollbackRepair(snapshot)
    }

    func recordPairingFailure() {
        pairingFailures += 1
        if pairingFailures >= 5 { cancelPairing() }
    }

    func consumePairing(code: String) -> Bool {
        guard let current = activePairingWindow(), current.code == code else { return false }
        cancelPairing()
        return true
    }

    private func sessionAuthenticated(_ sessionID: UUID, deviceID: UUID, generation: UInt64) async -> Bool {
        guard lifecycle.mayAuthorize(
            sessionID: sessionID,
            deviceID: deviceID,
            generation: generation
        ) else { return false }
        let credentialExists = (try? await credentialStore.load(deviceID)) != nil
        guard lifecycle.authorize(
            sessionID: sessionID,
            deviceID: deviceID,
            generation: generation,
            credentialExists: credentialExists
        ) else { return false }
        eventContinuation.yield(.connectionCountChanged(lifecycle.authenticatedCount))
        if let devices = try? await credentialStore.loadAll() {
            guard lifecycle.isAuthorized(
                sessionID: sessionID,
                deviceID: deviceID,
                generation: generation
            ) else { return false }
            eventContinuation.yield(.devicesChanged(devices))
        }
        return lifecycle.isAuthorized(
            sessionID: sessionID,
            deviceID: deviceID,
            generation: generation
        )
    }

    private func sessionEnded(_ id: UUID) async {
        let previousCount = lifecycle.authenticatedCount
        _ = lifecycle.end(sessionID: id)
        sessions.removeValue(forKey: id)
        await statusScheduler.remove(sessionID: id)
        if lifecycle.authenticatedCount != previousCount {
            eventContinuation.yield(.connectionCountChanged(lifecycle.authenticatedCount))
        }
    }

    private func evictSession(_ id: UUID) async {
        let previousCount = lifecycle.authenticatedCount
        _ = lifecycle.end(sessionID: id)
        let peer = sessions.removeValue(forKey: id)
        await statusScheduler.remove(sessionID: id)
        await peer?.close()
        if lifecycle.authenticatedCount != previousCount {
            eventContinuation.yield(.connectionCountChanged(lifecycle.authenticatedCount))
        }
    }

    private func listenerFailed(generation: UInt64) async {
        guard lifecycle.isActive(generation: generation) else { return }
        let sessionIDs = lifecycle.fail(generation: generation)
        let peers = sessionIDs.compactMap { sessions.removeValue(forKey: $0) }
        listener?.cancel()
        listener = nil
        configuration = nil
        if pairing != nil { cancelPairing() }
        eventContinuation.yield(.connectionCountChanged(0))
        eventContinuation.yield(.statusChanged(.failed("Remote access could not start")))
        for peer in peers { await peer.close() }
        await statusScheduler.stop()
    }

    var hasOwnedListener: Bool { listener != nil }

}

private final class HostContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Swift.Error>?

    init(_ continuation: CheckedContinuation<Void, Swift.Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Void) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Swift.Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Void, Swift.Error>? {
        lock.lock()
        defer { lock.unlock() }
        defer { continuation = nil }
        return continuation
    }
}
