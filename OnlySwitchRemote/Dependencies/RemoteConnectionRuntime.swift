import Foundation
import Network
import RemoteCore

actor RemoteConnectionRuntime {
    static let discoveryDescriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
        type: "_onlyswitch._tcp",
        domain: nil
    )

    nonisolated static func needsDiscovery(
        subscriberCount: Int,
        selectedMacID: UUID?
    ) -> Bool {
        subscriberCount > 0 || selectedMacID != nil
    }

    nonisolated static func discoveryFailure(for error: NWError) -> DiscoveryFailure {
        switch error {
        case let .posix(code):
            switch code {
            case .EPERM, .EACCES:
                return .localNetworkAccessNeeded
            case .ENETDOWN, .ENETUNREACH, .EHOSTDOWN, .EHOSTUNREACH, .ENOTCONN:
                return .networkUnavailable
            default:
                return .browserUnavailable
            }
        case let .dns(code) where code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied):
            // A denied Local Network permission reaches the browser as a Bonjour policy error.
            return .localNetworkAccessNeeded
        case .dns, .tls:
            return .browserUnavailable
        @unknown default:
            return .browserUnavailable
        }
    }

    typealias ActionDeadline = @Sendable (
        Duration,
        @escaping @Sendable () async throws -> RemoteActionResult
    ) async throws -> RemoteActionResult
    static let maximumCandidatesPerMac = 8
    static let maximumCandidatesGlobally = 64
    nonisolated let discoveryHub = RemoteStreamHub<DiscoveryEvent>()
    nonisolated let eventHub = RemoteStreamHub<RemoteConnectionEvent>()
    let persistence: RemotePersistenceClient
    let keychain: RemoteKeychainClient
    let deviceID: UUID
    let backgroundCleanup: @Sendable () async -> Void
    let catalogRequest: @Sendable (RemoteClientSession) async throws -> Void
    let closeSession: @Sendable (RemoteClientSession) async -> Void
    private let reconnectStarted: @Sendable () async -> Void
    let actionTimeout: Duration
    let actionDeadline: ActionDeadline
    private let screenshotCache: RemoteScreenshotCacheClient
    let backgroundTasks: RemoteBackgroundTaskClient
    let backgroundTransferGracePeriod: Duration
    let pairingDurableCommitCompleted: @Sendable () async -> Void
    let localStateMutations = RemoteLocalStateMutationCoordinator()
    var browser: NWBrowser?
    var browserRetryTask: Task<Void, Never>?
    var browserFailureCount = 0
    var browserGeneration: UInt64 = 0
    var discovered: [UUID: [String: DiscoveredMac]] = [:]
    var selected: PairedMac?
    var session: RemoteClientSession?
    var sessionToken: UUID?
    var pairingTask: Task<RemoteClientSession.PairingResult, Swift.Error>?
    var pairingToken: UUID?
    struct PreparingSession: Sendable {
        let session: RemoteClientSession
        let pairingToken: UUID
        let transactionID: UUID
    }
    var preparingSession: PreparingSession?
    struct PendingPreparedSession: Sendable {
        let session: RemoteClientSession
        var candidateSessionNeedsClose: Bool
        let sessionToken: UUID
        let pairingToken: UUID
        let generation: UInt64
        let macID: UUID
        let transactionID: UUID
        let mac: PairedMac
        let catalog: RemoteCatalogCache
        let candidateCredential: Data
        let persistenceRecord: PreparedPairingPersistenceRecord
        let endpoint: NWEndpoint
        let deviceName: String
    }
    var pendingPreparedSession: PendingPreparedSession?
    var finalizingTransactionID: UUID?
    enum LocalRevocationSource: Sendable { case live, offline }
    struct PendingRevocation: Sendable {
        let token: UUID
        let authenticatedSessionToken: UUID
        let generation: UInt64
        let macID: UUID
        let credential: Data
        let source: LocalRevocationSource
    }
    var pendingRevocation: PendingRevocation?
    var connectionTask: Task<Void, Never>?
    private var adoptingMacID: UUID?
    var generation: UInt64 = 0
    var foregrounded = true
    var foregroundLifecycleGeneration: UInt64 = 0
    /// Original downloads running inside `withBackgroundTransferHold`.
    var activeBackgroundTransfers = 0
    /// While backgrounded with transfers in flight, the session's close is deferred until they
    /// finish, the grace period ends, or iOS withdraws the background time.
    struct BackgroundHold {
        let id: UUID
        let timeout: Task<Void, Never>
        var task: RemoteBackgroundTaskClient.Token?
    }
    var backgroundHold: BackgroundHold?
    var aphroditeTransfers: [UUID: RemoteAphroditeTransferAccumulator] = [:]

    init(
        persistence: RemotePersistenceClient,
        keychain: RemoteKeychainClient,
        deviceID: UUID = RemoteDeviceIdentity.load(),
        backgroundCleanup: @escaping @Sendable () async -> Void = {},
        catalogRequest: @escaping @Sendable (RemoteClientSession) async throws -> Void = {
            try await $0.requestCatalog()
        },
        closeSession: @escaping @Sendable (RemoteClientSession) async -> Void = { await $0.close() },
        reconnectStarted: @escaping @Sendable () async -> Void = {},
        pairingDurableCommitCompleted: @escaping @Sendable () async -> Void = {},
        actionTimeout: Duration = .seconds(10),
        actionDeadline: @escaping ActionDeadline = { duration, operation in
            try await RemoteConnectionRuntime.withTimeout(duration, operation: operation)
        },
        screenshotCache: RemoteScreenshotCacheClient = .noop,
        backgroundTasks: RemoteBackgroundTaskClient = .noop,
        backgroundTransferGracePeriod: Duration = .seconds(30)
    ) {
        self.persistence = persistence
        self.keychain = keychain
        self.deviceID = deviceID
        self.backgroundCleanup = backgroundCleanup
        self.catalogRequest = catalogRequest
        self.closeSession = closeSession
        self.reconnectStarted = reconnectStarted
        self.pairingDurableCommitCompleted = pairingDurableCommitCompleted
        self.actionTimeout = actionTimeout
        self.actionDeadline = actionDeadline
        self.screenshotCache = screenshotCache
        self.backgroundTasks = backgroundTasks
        self.backgroundTransferGracePeriod = backgroundTransferGracePeriod
    }

    nonisolated func makeDiscoveryStream() -> AsyncStream<DiscoveryEvent> {
        discoveryHub.stream(
            bufferingPolicy: .bufferingNewest(64),
            onFirstSubscriber: { [weak self] in Task { await self?.startDiscovery() } },
            onNoSubscribers: { [weak self] in Task { await self?.stopDiscoveryIfUnused() } }
        )
    }

    nonisolated func makeConnectionEventStream() -> AsyncStream<RemoteConnectionEvent> {
        eventHub.stream(bufferingPolicy: .bufferingNewest(256))
    }

    func startDiscovery() {
        guard foregrounded,
              Self.needsDiscovery(
                  subscriberCount: discoveryHub.subscriberCount,
                  selectedMacID: selected?.id
              ),
              browser == nil else { return }
        let browser = NWBrowser(for: Self.discoveryDescriptor, using: .tcp)
        let expectedGeneration = browserGeneration
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { await self?.updateDiscovery(results, generation: expectedGeneration) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { await self?.browserBecameReady(generation: expectedGeneration) }
            case let .waiting(error):
                Task { await self?.publishWaiting(error, generation: expectedGeneration) }
            case let .failed(error):
                Task { await self?.publishFailureAndRestart(error, generation: expectedGeneration) }
            default:
                break
            }
        }
        discoveryHub.yield(.started)
        browser.start(queue: .global(qos: .userInitiated))
    }

    func restartDiscovery() {
        guard foregrounded else { return }
        browser?.cancel()
        browser = nil
        browserRetryTask?.cancel()
        browserRetryTask = nil
        browserFailureCount = 0
        browserGeneration &+= 1
        discovered.removeAll()
        startDiscovery()
    }

    func select(_ mac: PairedMac?) async {
        guard finalizingTransactionID == nil else { return }
        await abortPairing(nil)
        generation &+= 1
        let currentGeneration = generation
        connectionTask?.cancel()
        connectionTask = nil
        let previousSession = session
        session = nil
        sessionToken = nil
        selected = mac
        if mac == nil {
            stopDiscoveryIfUnused()
        } else {
            startDiscovery()
        }
        if let previousSession { await closeSession(previousSession) }
        guard generation == currentGeneration, selected?.id == mac?.id else { return }
        guard let mac, foregrounded else { return }
        connectionTask = Task { [weak self] in
            guard let self else { return }
            await self.reconnectStarted()
            await self.connectWithRetry(mac, generation: currentGeneration)
            await self.reconnectFinished(generation: currentGeneration)
        }
    }

    private func reconnectFinished(generation expectedGeneration: UInt64) {
        guard generation == expectedGeneration else { return }
        connectionTask = nil
    }

    func snapshot() -> RemoteConnectionSnapshot {
        .init(
            selectedMacID: selected?.id,
            authenticatedMacID: session == nil ? nil : selected?.id,
            authenticatedSessionID: session == nil ? nil : sessionToken
        )
    }

    func adoptPairedMac(_ mac: PairedMac) async -> RemotePairAdoptionResult {
        if selected == mac, session != nil, sessionToken != nil {
            return .authenticated
        }
        if adoptingMacID == mac.id || (selected?.id == mac.id && connectionTask != nil) {
            return .connecting
        }
        adoptingMacID = mac.id
        await select(mac)
        if adoptingMacID == mac.id { adoptingMacID = nil }
        guard selected?.id == mac.id, connectionTask != nil else { return .offline }
        return .connecting
    }

    func forgetMac(_ id: UUID) async throws {
        guard finalizingTransactionID == nil else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing finalization is in progress")
        }
        await abortPairing(nil)
        let coordinator = localStateMutations
        try await coordinator.run { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.performForget(id)
        }
    }

    private func performForget(_ id: UUID) async throws {
        try await persistence.markMacTombstoned(id)
        await screenshotCache.removeMac(id)

        generation &+= 1
        connectionTask?.cancel()
        pairingTask?.cancel()
        connectionTask = nil
        pairingTask = nil
        pairingToken = nil
        pendingRevocation = nil
        aphroditeTransfers.removeAll()

        let detachedSession = selected?.id == id ? session : nil
        if selected?.id == id { selected = nil }
        if detachedSession != nil {
            session = nil
            sessionToken = nil
        }
        if let detachedSession { await closeSession(detachedSession) }

        try await keychain.deleteCredential(id)
        try await persistence.forgetMac(id)
    }
}
