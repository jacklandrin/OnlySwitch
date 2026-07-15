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
    private let eventStream: AsyncStream<RemoteHostEvent>
    private let eventContinuation: AsyncStream<RemoteHostEvent>.Continuation
    private var listener: NWListener?
    private var configuration: RemoteHostConfiguration?
    private var pairing: PairingWindow?
    private var pairingFailures = 0
    private var sessions: [UUID: RemotePeerSession] = [:]
    private var authenticatedDevices: [UUID: UUID] = [:]
    private let statusScheduler: RemoteStatusScheduler

    nonisolated var events: AsyncStream<RemoteHostEvent> { eventStream }

    private init(
        credentialStore: RemoteCredentialStore,
        catalogProvider: RemoteCatalogProvider,
        router: RemoteCommandRouter,
        fixedPairingCode: String? = nil
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
        self.statusScheduler = RemoteStatusScheduler(provider: catalogProvider)
    }

    deinit {
        eventContinuation.finish()
    }

    static func testing(
        catalog: [RemoteControlDescriptor],
        router: RemoteCommandRouter,
        pairingCode: String
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
            fixedPairingCode: pairingCode
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
        listener?.cancel()
        listener = nil
        if pairing != nil { cancelPairing() }
        let peers = Array(sessions.values)
        sessions.removeAll()
        authenticatedDevices.removeAll()
        for peer in peers { await peer.close() }
        await statusScheduler.stop()
        configuration = nil
        eventContinuation.yield(.connectionCountChanged(0))
        eventContinuation.yield(.statusChanged(.stopped))
    }

    func startPairing() -> PairingWindow {
        let window = PairingWindow(
            code: fixedPairingCode ?? PairingCode.generate(),
            expiresAt: Date().addingTimeInterval(300)
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
        try await credentialStore.delete(deviceID)
        let affected = authenticatedDevices.compactMap { $0.value == deviceID ? $0.key : nil }
        for sessionID in affected {
            await sessions[sessionID]?.close()
            await sessionEnded(sessionID)
        }
        eventContinuation.yield(.devicesChanged(try await credentialStore.loadAll()))
    }

    func pairedDevices() async throws -> [PairedRemoteDevice] {
        try await credentialStore.loadAll()
    }

    private func startListener(
        configuration: RemoteHostConfiguration,
        advertise: Bool
    ) async throws -> NWEndpoint {
        if listener != nil { await stop() }
        eventContinuation.yield(.statusChanged(.starting))
        let port = configuration.port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: configuration.port)!
        let listener = try NWListener(using: .tcp, on: port)
        let macID = try await credentialStore.installationID()
        if advertise {
            let txt = NWTXTRecord([
                "id": macID.uuidString,
                "version": String(RemoteProtocolVersion.current.major)
            ])
            listener.service = NWListener.Service(
                name: configuration.displayName,
                type: configuration.serviceType,
                txtRecord: txt
            )
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection, macID: macID, name: configuration.displayName) }
        }
        self.listener = listener
        self.configuration = configuration
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                    let gate = ContinuationGate(continuation)
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready: gate.resume(returning: ())
                        case let .failed(error): gate.resume(throwing: error)
                        case .cancelled: gate.resume(throwing: CancellationError())
                        default: break
                        }
                    }
                    listener.start(queue: .global(qos: .userInitiated))
                }
            } onCancel: {
                listener.cancel()
            }
        } catch {
            self.listener = nil
            eventContinuation.yield(.statusChanged(.failed("Remote access could not start")))
            throw error
        }
        guard let boundPort = listener.port else {
            listener.cancel()
            throw RemoteProtocolError(code: .invalidFrame, message: "Listener did not bind")
        }
        eventContinuation.yield(.statusChanged(.listening(port: boundPort.rawValue)))
        return .hostPort(host: .ipv4(.loopback), port: boundPort)
    }

    private func accept(_ connection: NWConnection, macID: UUID, name: String) {
        let sessionID = UUID()
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
            subscriptionsChanged: { [weak self] id, ids, sink in
                await self?.statusScheduler.update(sessionID: id, ids: ids, sink: sink)
            },
            refreshRequested: { [weak self] id in
                await self?.statusScheduler.refresh(id)
            },
            authenticated: { [weak self] sessionID, deviceID in
                await self?.sessionAuthenticated(sessionID, deviceID: deviceID) ?? false
            },
            ended: { [weak self] id in await self?.sessionEnded(id) }
        )
        sessions[sessionID] = peer
        eventContinuation.yield(.connectionCountChanged(sessions.count))
        Task { await peer.run() }
    }

    private func activePairingWindow() -> PairingWindow? {
        guard let pairing, pairing.expiresAt > Date(), pairingFailures < 5 else {
            if self.pairing != nil {
                self.pairing = nil
                eventContinuation.yield(.pairingChanged(nil))
            }
            return nil
        }
        return pairing
    }

    private func recordPairingFailure() {
        pairingFailures += 1
        if pairingFailures >= 5 { cancelPairing() }
    }

    private func consumePairing(code: String) -> Bool {
        guard let current = activePairingWindow(), current.code == code else { return false }
        cancelPairing()
        return true
    }

    private func sessionAuthenticated(_ sessionID: UUID, deviceID: UUID) async -> Bool {
        guard (try? await credentialStore.load(deviceID)) != nil else { return false }
        authenticatedDevices[sessionID] = deviceID
        if let devices = try? await credentialStore.loadAll() {
            eventContinuation.yield(.devicesChanged(devices))
        }
        return true
    }

    private func sessionEnded(_ id: UUID) async {
        guard sessions.removeValue(forKey: id) != nil else { return }
        authenticatedDevices[id] = nil
        await statusScheduler.remove(sessionID: id)
        eventContinuation.yield(.connectionCountChanged(sessions.count))
    }
}
