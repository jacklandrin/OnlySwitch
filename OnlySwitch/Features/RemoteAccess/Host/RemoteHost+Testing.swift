import Foundation
import Network
import RemoteCore
import RemoteTransport
import SystemMonitor

extension RemoteHost {
    static func testing(
        catalog: [RemoteControlDescriptor],
        catalogProvider injectedCatalogProvider: RemoteCatalogProvider? = nil,
        router: RemoteCommandRouter,
        pairingCode: String,
        peerDeadlines: RemotePeerDeadlines = .init(),
        credentialStore: RemoteCredentialStore? = nil,
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
        finalizeRepairObserver: @escaping @Sendable (UUID) -> Void = { _ in },
        systemMonitorSnapshots: @escaping @Sendable () -> AsyncThrowingStream<SystemMonitorSnapshot, Error> = {
            MacSystemMonitorCollector.liveClient().snapshots()
        },
        soundMixerSnapshots: @escaping @Sendable () -> AsyncThrowingStream<RemoteSoundMixerSnapshot, Error> = {
            AsyncThrowingStream {
                $0.finish(throwing: RemoteProtocolError(code: .actionNotSupported, message: "Sound Mixer is unavailable"))
            }
        },
        soundMixerCommand: @escaping @Sendable (RemoteSoundMixerCommand) async throws -> RemoteSoundMixerSnapshot = { _ in
            throw RemoteProtocolError(code: .actionNotSupported, message: "Sound Mixer is unavailable")
        },
        brightnessSnapshots: @escaping @Sendable (UUID) -> AsyncStream<RemoteBrightnessSnapshot> = { _ in
            AsyncStream { $0.finish() }
        },
        brightnessCommand: @escaping @Sendable (RemoteBrightnessCommand) async throws -> RemoteBrightnessSnapshot = { _ in
            throw RemoteProtocolError(code: .actionNotSupported, message: "Brightness is unavailable")
        },
        screenshots: RemoteScreenshotsService = .unavailable,
        codexUsage: @escaping @Sendable (Bool) async -> Result<RemoteCodexUsageSnapshot, RemoteProtocolError> = { _ in
            .failure(.init(code: .actionNotSupported, message: "Codex usage is unavailable"))
        },
        claudeUsage: @escaping @Sendable () async -> Result<RemoteClaudeUsageSnapshot, RemoteProtocolError> = {
            .failure(.init(code: .actionNotSupported, message: "Claude usage is unavailable"))
        }
    ) -> RemoteHost {
        let fixedProvider = RemoteCatalogProvider(
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
        let provider = injectedCatalogProvider ?? fixedProvider
        return RemoteHost(
            credentialStore: credentialStore ?? .inMemory(finalizeRepairObserver: finalizeRepairObserver),
            catalogProvider: provider,
            router: router,
            fixedPairingCode: pairingCode,
            peerDeadlines: peerDeadlines,
            listenerFactory: listenerFactory,
            installationIDProvider: installationIDProvider,
            revocationPrepared: revocationPrepared,
            authenticationResultSender: authenticationResultSender,
            commitStageReached: commitStageReached,
            authenticatedSessionObserver: authenticatedSessionObserver,
            systemMonitorSnapshots: systemMonitorSnapshots,
            soundMixerSnapshots: soundMixerSnapshots,
            soundMixerCommand: soundMixerCommand,
            brightnessSnapshots: brightnessSnapshots,
            brightnessCommand: brightnessCommand,
            screenshots: screenshots,
            codexUsage: codexUsage,
            claudeUsage: claudeUsage
        )
    }

    func pairingTransactionStateForTesting(_ transactionID: UUID) async throws -> PairingTransactionState {
        try await credentialStore.transactionStatus(transactionID)
    }

    func revokePreservingCredentialForTesting(deviceID: UUID) async throws {
        guard try await credentialStore.prepareRevocation(deviceID) != nil else { return }
        let affected = lifecycle.revoke(deviceID: deviceID)
        let peers = affected.compactMap { sessions.removeValue(forKey: $0) }
        for peer in peers { await peer.close() }
    }

    func revocationVerifierForTesting(deviceID: UUID) async throws -> Data? {
        try await credentialStore.loadRevocationVerifier(deviceID)
    }

    func isRevokedForTesting(deviceID: UUID) -> Bool {
        lifecycle.isRevoked(deviceID)
    }

    func deleteCredentialForTesting(deviceID: UUID, matching credential: Data) async throws {
        try await credentialStore.delete(deviceID, matchingCredential: credential)
    }

    @discardableResult
    func refreshCatalogForTesting() async throws -> RemoteCatalogSnapshot? {
        try await catalogMonitor.refresh()
    }

    func closeSessionsForTesting() async {
        let peers = Array(sessions.values)
        for peer in peers { await peer.close() }
    }

    func authenticatedSessionCountForTesting() -> Int {
        lifecycle.authenticatedCount
    }
}
