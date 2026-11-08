import CryptoKit
import Aphrodite
import Foundation
import Network
import RemoteCore
import RemoteTransport

actor RemotePeerSession {
    typealias AuthenticationResultSender = @Sendable (
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws -> Void

    struct PendingPairing: Sendable {
        let transactionID: UUID
        let record: PairedRemoteDevice
        let snapshot: RemotePairingSnapshot
        let expiresAt: Date
    }

    enum State: Sendable {
        case awaitingHello
        case awaitingPairOrAuthentication
        case provisional(UUID, UUID)
        case committing(UUID, UUID)
        case authenticated(UUID)
        case closed
    }

    let id: UUID
    let io: RemoteConnectionIO
    let macID: UUID
    let macName: String
    let credentialStore: RemoteCredentialStore
    let catalogSnapshot: @Sendable () async throws -> RemoteCatalogSnapshot
    let router: RemoteCommandRouter
    let pairingWindow: @Sendable () async -> PairingWindow?
    let pairingFailed: @Sendable () async -> Void
    let consumePairing: @Sendable (String) async -> Bool
    private let pairingEpoch: @Sendable (UUID) async -> UInt64
    let pairingSnapshot: @Sendable (UUID) async -> RemotePairingSnapshot?
    let validatePairing: @Sendable (RemotePairingSnapshot) async -> Bool
    let commitPairing: @Sendable (RemotePairingSnapshot) async -> Bool
    let rollbackPairing: @Sendable (RemotePairingSnapshot) async -> Bool
    let subscriptionsChanged: @Sendable (UUID, Set<RemoteControlID>, @escaping RemoteStatusScheduler.Sink) async throws -> Void
    let refreshRequested: @Sendable (RemoteControlID) async -> Void
    let authenticated: @Sendable (UUID, UUID) async -> Bool
    let authenticationAuthorized: @Sendable (UUID, UUID) async -> Bool
    let authenticationConfirmed: @Sendable (UUID, UUID) async -> Bool
    let systemMonitorSnapshots: @Sendable () -> AsyncThrowingStream<SystemMonitorSnapshot, Error>
    let soundMixerSnapshots: @Sendable () -> AsyncThrowingStream<RemoteSoundMixerSnapshot, Error>
    let soundMixerCommand: @Sendable (RemoteSoundMixerCommand) async throws -> RemoteSoundMixerSnapshot
    let brightnessSnapshots: @Sendable (UUID) -> AsyncStream<RemoteBrightnessSnapshot>
    let brightnessCommand: @Sendable (RemoteBrightnessCommand) async throws -> RemoteBrightnessSnapshot
    let screenshots: RemoteScreenshotsService
    let claudeUsage: @Sendable () async -> Result<RemoteClaudeUsageSnapshot, RemoteProtocolError>
    let codexUsage: @Sendable (Bool) async -> Result<RemoteCodexUsageSnapshot, RemoteProtocolError>
    let aphroditeSnapshotMessages: @Sendable () async throws -> [RemoteMessage]
    let authenticationResultSender: AuthenticationResultSender
    let commitStageReached: @Sendable (RemotePairingCommitStage) async -> Void
    private let ended: @Sendable (UUID) async -> Void
    let deadlines: RemotePeerDeadlines
    var state: State = .awaitingHello
    var crypto: RemoteSessionCrypto?
    var pendingPairing: PendingPairing?
    var authenticatedCredential: Data?
    var negotiatedVersion: RemoteProtocolVersion?
    var advertisedCatalogRevision: UInt64?
    var systemMonitorTask: Task<Void, Never>?
    var soundMixerTask: Task<Void, Never>?
    var brightnessTask: Task<Void, Never>?
    var screenshotsLibraryTask: Task<Void, Never>?
    /// Thumbnail requests run serially; each new one chains after the previous.
    var screenshotThumbnailsTask: Task<Void, Never>?
    /// At most one original is transferred; a newer request cancels the older one.
    var screenshotImageTask: Task<Void, Never>?
    var claudeUsageTask: Task<Void, Never>?
    var claudeUsageGeneration: UInt64 = 0
    var codexUsageTask: Task<Void, Never>?
    var codexUsageGeneration: UInt64 = 0
    var aphroditeChangesTask: Task<Void, Never>?

    init(
        id: UUID = UUID(),
        connection: NWConnection,
        macID: UUID,
        macName: String,
        credentialStore: RemoteCredentialStore,
        catalogSnapshot: @escaping @Sendable () async throws -> RemoteCatalogSnapshot,
        router: RemoteCommandRouter,
        pairingWindow: @escaping @Sendable () async -> PairingWindow?,
        pairingFailed: @escaping @Sendable () async -> Void,
        consumePairing: @escaping @Sendable (String) async -> Bool,
        pairingEpoch: @escaping @Sendable (UUID) async -> UInt64,
        pairingSnapshot: @escaping @Sendable (UUID) async -> RemotePairingSnapshot?,
        validatePairing: @escaping @Sendable (RemotePairingSnapshot) async -> Bool,
        commitPairing: @escaping @Sendable (RemotePairingSnapshot) async -> Bool,
        rollbackPairing: @escaping @Sendable (RemotePairingSnapshot) async -> Bool,
        subscriptionsChanged: @escaping @Sendable (UUID, Set<RemoteControlID>, @escaping RemoteStatusScheduler.Sink) async throws -> Void,
        refreshRequested: @escaping @Sendable (RemoteControlID) async -> Void,
        authenticated: @escaping @Sendable (UUID, UUID) async -> Bool,
        authenticationAuthorized: @escaping @Sendable (UUID, UUID) async -> Bool,
        authenticationConfirmed: @escaping @Sendable (UUID, UUID) async -> Bool,
        systemMonitorSnapshots: @escaping @Sendable () -> AsyncThrowingStream<SystemMonitorSnapshot, Error>,
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
        },
        aphroditeSnapshotMessages: @escaping @Sendable () async throws -> [RemoteMessage] = {
            try await RemoteAphroditeSnapshotProvider.liveMessages()
        },
        authenticationResultSender: @escaping AuthenticationResultSender = { operation in
            try await operation()
        },
        commitStageReached: @escaping @Sendable (RemotePairingCommitStage) async -> Void = { _ in },
        ended: @escaping @Sendable (UUID) async -> Void,
        deadlines: RemotePeerDeadlines = .init()
    ) {
        self.id = id
        self.io = RemoteConnectionIO(connection: connection)
        self.macID = macID
        self.macName = macName
        self.credentialStore = credentialStore
        self.catalogSnapshot = catalogSnapshot
        self.router = router
        self.pairingWindow = pairingWindow
        self.pairingFailed = pairingFailed
        self.consumePairing = consumePairing
        self.pairingEpoch = pairingEpoch
        self.pairingSnapshot = pairingSnapshot
        self.validatePairing = validatePairing
        self.commitPairing = commitPairing
        self.rollbackPairing = rollbackPairing
        self.subscriptionsChanged = subscriptionsChanged
        self.refreshRequested = refreshRequested
        self.authenticated = authenticated
        self.authenticationAuthorized = authenticationAuthorized
        self.authenticationConfirmed = authenticationConfirmed
        self.systemMonitorSnapshots = systemMonitorSnapshots
        self.soundMixerSnapshots = soundMixerSnapshots
        self.soundMixerCommand = soundMixerCommand
        self.brightnessSnapshots = brightnessSnapshots
        self.brightnessCommand = brightnessCommand
        self.screenshots = screenshots
        self.codexUsage = codexUsage
        self.claudeUsage = claudeUsage
        self.aphroditeSnapshotMessages = aphroditeSnapshotMessages
        self.authenticationResultSender = authenticationResultSender
        self.commitStageReached = commitStageReached
        self.ended = ended
        self.deadlines = deadlines
    }

    func run() async {
        do {
            try await Self.withTimeout(deadlines.handshake) { [self] in
                try await io.start()
                try await handshake()
            }
            try await messageLoop()
        } catch {
            // Protocol and network failures intentionally close without exposing secrets.
        }
        if RemotePairingTeardownPolicy.action(for: teardownPhase) == .preserveDurablePreparedTransaction {
            pendingPairing = nil
        } else {
            await rollbackPendingPairingIfNeeded()
        }
        stopSystemMonitorStreaming()
        stopSoundMixerStreaming()
        stopBrightnessStreaming()
        stopScreenshotsStreaming()
        codexUsageTask?.cancel()
        codexUsageTask = nil
        claudeUsageTask?.cancel()
        claudeUsageTask = nil
        claudeUsageGeneration &+= 1
        aphroditeChangesTask?.cancel()
        aphroditeChangesTask = nil
        state = .closed
        await io.cancel()
        await ended(id)
    }

    func close() async {
        if RemotePairingTeardownPolicy.action(for: teardownPhase) == .preserveDurablePreparedTransaction {
            pendingPairing = nil
        }
        stopSystemMonitorStreaming()
        stopSoundMixerStreaming()
        stopBrightnessStreaming()
        stopScreenshotsStreaming()
        codexUsageTask?.cancel()
        codexUsageTask = nil
        claudeUsageTask?.cancel()
        claudeUsageTask = nil
        claudeUsageGeneration &+= 1
        aphroditeChangesTask?.cancel()
        aphroditeChangesTask = nil
        state = .closed
        await io.cancel()
        await ended(id)
    }

    private var teardownPhase: RemotePairingTeardownPhase {
        switch state {
        case .provisional: .provisional
        case .committing: .committing
        case .authenticated: .authenticated
        case .awaitingHello, .awaitingPairOrAuthentication, .closed: .other
        }
    }

    func revoke(deadline: Duration = .seconds(2)) async {
        guard case .authenticated = state,
              negotiatedVersion?.supportsAuthenticatedRevocation == true else {
            await close()
            return
        }
        await Self.notifyRevocation(
            deadline: deadline,
            send: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.sendEncrypted(.credentialRevoked)
            },
            close: { [weak self] in await self?.close() }
        )
    }

    func sendStatus(_ status: RemoteControlStatus) async throws {
        try await sendEncrypted(.statusChanged(status))
    }

    static func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw CancellationError()
            }
            guard let value = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return value
        }
    }

    static func notifyRevocation(
        deadline: Duration,
        send: @escaping @Sendable () async throws -> Void,
        close: @escaping @Sendable () async -> Void
    ) async {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await send() }
                group.addTask {
                    try await Task.sleep(for: deadline)
                    await close()
                    throw CancellationError()
                }
                _ = try await group.next()
                group.cancelAll()
            }
        } catch {
        }
        await close()
    }

    static func makeCrypto(
        role: RemotePeerRole,
        privateKey: P256.KeyAgreement.PrivateKey,
        peerKey: Data,
        credential: Data,
        transcript: Data
    ) throws -> RemoteSessionCrypto {
        let keys = try RemoteSessionCrypto.deriveSessionKeys(
            role: role,
            privateKey: privateKey,
            peerPublicKey: peerKey,
            credential: credential,
            transcript: transcript
        )
        return RemoteSessionCrypto(sendKey: keys.send, receiveKey: keys.receive, noncePrefix: UInt32.random(in: .min ... .max))
    }

    static func randomData(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max) })
    }

    static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
        return difference == 0
    }
}
