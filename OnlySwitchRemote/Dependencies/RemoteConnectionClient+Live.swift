import CryptoKit
import Foundation
import Network
import RemoteCore
import RemoteTransport

extension RemoteConnectionClient {
    static var live: Self {
        let runtime = RemoteConnectionRuntime(
            persistence: .live,
            keychain: .live
        )
        return Self(
            discover: { runtime.makeDiscoveryStream() },
            preparePairing: { try await runtime.preparePairing($0, code: $1, deviceName: $2) },
            finalizePairing: { try await runtime.finalizePairing($0) },
            abortPairing: { await runtime.abortPairing($0) },
            select: { await runtime.select($0) },
            events: { runtime.makeConnectionEventStream() },
            snapshot: { await runtime.snapshot() },
            adoptPairedMac: { await runtime.adoptPairedMac($0) },
            forgetMac: { try await runtime.forgetMac($0) },
            subscribe: { try await runtime.subscribe($0) },
            send: { try await runtime.send($0) },
            setForegrounded: { await runtime.setForegrounded($0) }
        )
    }
}

final class RemoteStreamHub<Element: Sendable>: @unchecked Sendable {
    typealias Continuation = AsyncStream<Element>.Continuation

    private struct Subscriber {
        let continuation: Continuation
        let onNoSubscribers: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var subscribers: [UUID: Subscriber] = [:]

    var subscriberCount: Int {
        lock.withLock { subscribers.count }
    }

    func stream(
        bufferingPolicy: Continuation.BufferingPolicy,
        onFirstSubscriber: @escaping @Sendable () -> Void = {},
        onNoSubscribers: @escaping @Sendable () -> Void = {}
    ) -> AsyncStream<Element> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: Element.self,
            bufferingPolicy: bufferingPolicy
        )
        continuation.onTermination = { [weak self] _ in self?.removeSubscriber(id) }
        let isFirst = lock.withLock { () -> Bool in
            let isFirst = subscribers.isEmpty
            subscribers[id] = Subscriber(
                continuation: continuation,
                onNoSubscribers: onNoSubscribers
            )
            return isFirst
        }
        if isFirst { onFirstSubscriber() }
        return stream
    }

    func yield(_ element: Element) {
        let continuations = lock.withLock { subscribers.values.map(\.continuation) }
        for continuation in continuations { continuation.yield(element) }
    }

    private func removeSubscriber(_ id: UUID) {
        let onNoSubscribers = lock.withLock { () -> (@Sendable () -> Void)? in
            guard let removed = subscribers.removeValue(forKey: id), subscribers.isEmpty else { return nil }
            return removed.onNoSubscribers
        }
        onNoSubscribers?()
    }
}

actor RemoteLocalStateMutationCoordinator {
    private var tail: Task<Void, Never>?

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let preceding = tail
        let task = Task<Value, Swift.Error> {
            if let preceding { await preceding.value }
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}

actor RemoteConnectionRuntime {
    typealias ActionDeadline = @Sendable (
        Duration,
        @escaping @Sendable () async throws -> RemoteActionResult
    ) async throws -> RemoteActionResult
    static let maximumCandidatesPerMac = 8
    static let maximumCandidatesGlobally = 64
    private nonisolated let discoveryHub = RemoteStreamHub<DiscoveryEvent>()
    private nonisolated let eventHub = RemoteStreamHub<RemoteConnectionEvent>()
    private let persistence: RemotePersistenceClient
    private let keychain: RemoteKeychainClient
    private let deviceID: UUID
    private let backgroundCleanup: @Sendable () async -> Void
    private let catalogRequest: @Sendable (RemoteClientSession) async throws -> Void
    private let closeSession: @Sendable (RemoteClientSession) async -> Void
    private let reconnectStarted: @Sendable () async -> Void
    private let actionTimeout: Duration
    private let actionDeadline: ActionDeadline
    private let pairingDurableCommitCompleted: @Sendable () async -> Void
    private let localStateMutations = RemoteLocalStateMutationCoordinator()
    private var browser: NWBrowser?
    private var browserRetryTask: Task<Void, Never>?
    private var browserFailureCount = 0
    private var browserGeneration: UInt64 = 0
    private var discovered: [UUID: [String: DiscoveredMac]] = [:]
    private var selected: PairedMac?
    private var session: RemoteClientSession?
    private var sessionToken: UUID?
    private var pairingTask: Task<RemoteClientSession.PairingResult, Swift.Error>?
    private var pairingToken: UUID?
    private struct PreparingSession: Sendable {
        let session: RemoteClientSession
        let pairingToken: UUID
        let transactionID: UUID
    }
    private var preparingSession: PreparingSession?
    private struct PendingPreparedSession: Sendable {
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
    private var pendingPreparedSession: PendingPreparedSession?
    private var finalizingTransactionID: UUID?
    enum LocalRevocationSource: Sendable { case live, offline }
    private struct PendingRevocation: Sendable {
        let token: UUID
        let authenticatedSessionToken: UUID
        let generation: UInt64
        let macID: UUID
        let credential: Data
        let source: LocalRevocationSource
    }
    private var pendingRevocation: PendingRevocation?
    private var connectionTask: Task<Void, Never>?
    private var adoptingMacID: UUID?
    private var generation: UInt64 = 0
    private var foregrounded = true
    private var foregroundLifecycleGeneration: UInt64 = 0

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
        }
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
        guard foregrounded, discoveryHub.subscriberCount > 0, browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_onlyswitch._tcp", domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { await self?.updateDiscovery(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: Task { await self?.browserBecameReady() }
            case .failed: Task { await self?.scheduleBrowserRestart() }
            default: break
            }
        }
        browser.start(queue: .global(qos: .userInitiated))
    }

    func preparePairing(_ mac: DiscoveredMac, code: String, deviceName: String) async throws -> PreparedPairing {
        guard mac.protocolVersion.isCompatible(with: .current),
              mac.protocolVersion.supportsTransactionalPairing else {
            throw RemoteProtocolError(code: .upgradeRequired, message: "Update OnlySwitch on this Mac to pair")
        }
        let cleanName = try Self.validatedDeviceName(deviceName)
        await abortPairing(nil)
        guard pairingToken == nil,
              preparingSession == nil,
              pendingPreparedSession == nil else {
            throw RemoteProtocolError(
                code: .authenticationFailed,
                message: "Previous pairing rollback is incomplete"
            )
        }
        guard foregrounded else { throw CancellationError() }
        let deviceID = self.deviceID
        let pairingToken = UUID()
        self.pairingToken = pairingToken
        let newSessionToken = UUID()
        let task = Task {
            try await Self.withTimeout(.seconds(15)) {
                try await RemoteClientSession.preparePairing(
                    endpoint: mac.endpoint,
                    expectedMacID: mac.id,
                    code: code.uppercased(),
                    deviceID: deviceID,
                    deviceName: cleanName,
                    sessionToken: newSessionToken,
                    event: { [weak self] message in
                        await self?.handle(message, macID: mac.id, sessionToken: newSessionToken)
                    },
                    disconnected: { [weak self] error in
                        await self?.sessionDisconnected(macID: mac.id, sessionToken: newSessionToken, error: error)
                    }
                )
            }
        }
        pairingTask = task
        let result: RemoteClientSession.PairingResult
        do {
            result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
                Task { await self.abortPairing(token: pairingToken) }
            }
        } catch {
            await abortPairing(token: pairingToken)
            throw error
        }
        guard result.credential.count == 32 else {
            await result.session.close()
            await abortPairing(token: pairingToken)
            throw RemoteKeychainClient.Error.invalidCredentialLength
        }
        guard self.pairingToken == pairingToken, foregrounded, Task.isCancelled == false else {
            await result.session.close()
            throw CancellationError()
        }
        preparingSession = .init(
            session: result.session,
            pairingToken: pairingToken,
            transactionID: result.transactionID
        )
        let value = PairedMac(
            id: mac.id,
            displayName: mac.displayName,
            lastEndpointDescription: String(describing: mac.endpoint),
            lastConnectedAt: .now,
            requiresPairing: false
        )
        let catalog: RemoteCatalogCache
        do { catalog = try await Self.withTimeout(.seconds(10)) { try await result.session.receiveCatalog() } }
        catch {
            if self.pairingToken == pairingToken {
                preparingSession = nil
                self.pairingToken = nil
                await result.session.abortPairing(result.transactionID)
                await closeSession(result.session)
                throw error
            }
            throw CancellationError()
        }
        do {
            try Self.validateCatalog(catalog, minimumRevision: result.catalogRevision)
        } catch {
            if self.pairingToken == pairingToken {
                preparingSession = nil
                self.pairingToken = nil
                await result.session.abortPairing(result.transactionID)
                await closeSession(result.session)
                throw error
            }
            throw CancellationError()
        }
        guard self.pairingToken == pairingToken, foregrounded, Task.isCancelled == false else {
            if self.pairingToken == pairingToken {
                preparingSession = nil
                self.pairingToken = nil
                await result.session.abortPairing(result.transactionID)
                await closeSession(result.session)
            }
            throw CancellationError()
        }
        let persistenceRecord: PreparedPairingPersistenceRecord
        let credentialVerifier = RemoteKeychainClient.credentialVerifier(result.credential)
        do {
            persistenceRecord = try await localStateMutations.run { [keychain, persistence] in
                try await keychain.saveProvisionalCredential(result.transactionID, result.credential)
                do {
                    return try await persistence.preparePairingState(value, result.transactionID, credentialVerifier)
                } catch {
                    _ = try? await keychain.deleteProvisionalCredential(result.transactionID, credentialVerifier)
                    throw error
                }
            }
        } catch {
            guard self.pairingToken == pairingToken else { throw CancellationError() }
            pairingTask = nil
            preparingSession = nil
            self.pairingToken = nil
            await result.session.abortPairing(result.transactionID)
            await closeSession(result.session)
            throw error
        }
        pairingTask = nil
        preparingSession = nil
        pendingPreparedSession = PendingPreparedSession(
            session: result.session, candidateSessionNeedsClose: true,
            sessionToken: newSessionToken, pairingToken: pairingToken,
            generation: generation, macID: mac.id, transactionID: result.transactionID,
            mac: value, catalog: catalog, candidateCredential: result.credential,
            persistenceRecord: persistenceRecord,
            endpoint: mac.endpoint, deviceName: cleanName
        )
        await pairingDurableCommitCompleted()
        guard self.pairingToken == pairingToken,
              pendingPreparedSession?.transactionID == result.transactionID,
              foregrounded,
              Task.isCancelled == false else {
            if self.pairingToken == pairingToken {
                await abortPairing(token: pairingToken, transactionID: result.transactionID)
            }
            throw CancellationError()
        }
        return PreparedPairing(transactionID: result.transactionID, mac: value, catalog: catalog)
    }

    func finalizePairing(_ transactionID: UUID) async throws -> PairedMac {
        guard var pending = pendingPreparedSession, pending.transactionID == transactionID else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing transaction is unavailable")
        }
        guard finalizingTransactionID == nil || finalizingTransactionID == transactionID else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "Another pairing transaction is finalizing")
        }
        finalizingTransactionID = transactionID
        try await persistence.adoptPreparedPairingState(transactionID)
        var state: PairingTransactionState
        do {
            let committingSession = pending.session
            state = try await Self.withTimeout(.seconds(10)) { try await committingSession.commitPairing(transactionID) }
        } catch {
            do {
                let provisionalSession = pending.session
                state = try await Self.withTimeout(.seconds(10)) {
                    try await provisionalSession.resolvePairing(transactionID)
                }
            } catch {
                let recoveryPending = pending
                let recovery = try await RemoteClientSession.authenticate(
                    endpoint: recoveryPending.endpoint, expectedMacID: recoveryPending.macID,
                    credential: recoveryPending.candidateCredential, deviceID: deviceID,
                    deviceName: recoveryPending.deviceName, sessionToken: recoveryPending.sessionToken,
                    event: { [weak self] message in
                        await self?.handle(message, macID: recoveryPending.macID, sessionToken: recoveryPending.sessionToken)
                    },
                    disconnected: { [weak self] error in
                        await self?.sessionDisconnected(macID: recoveryPending.macID, sessionToken: recoveryPending.sessionToken, error: error)
                    }
                )
                await pending.session.close()
                pending = PendingPreparedSession(
                    session: recovery, candidateSessionNeedsClose: true,
                    sessionToken: pending.sessionToken, pairingToken: pending.pairingToken,
                    generation: pending.generation, macID: pending.macID, transactionID: pending.transactionID,
                    mac: pending.mac, catalog: pending.catalog, candidateCredential: pending.candidateCredential,
                    persistenceRecord: pending.persistenceRecord,
                    endpoint: pending.endpoint, deviceName: pending.deviceName
                )
                pendingPreparedSession = pending
                state = try await Self.withTimeout(.seconds(10)) { try await recovery.resolvePairing(transactionID) }
            }
        }
        guard state == .committed else {
            if state == .aborted {
                finalizingTransactionID = nil
                await abortPairing(transactionID)
            }
            throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing was not committed")
        }
        let committedPending = pending
        try await localStateMutations.run { [keychain, persistence] in
            guard try await keychain.promoteProvisionalCredential(
                transactionID,
                committedPending.macID,
                committedPending.persistenceRecord.candidateCredentialVerifier
            ) else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing credential ownership changed")
            }
            try await persistence.finalizePairingState(transactionID)
        }
        guard pendingPreparedSession?.transactionID == transactionID else { throw CancellationError() }
        generation &+= 1
        connectionTask?.cancel()
        connectionTask = nil
        let previousSession = session
        session = pending.session
        sessionToken = pending.sessionToken
        selected = pending.mac
        pairingToken = nil
        pendingPreparedSession = nil
        eventHub.yield(.sessionStarted(pending.macID, pending.sessionToken))
        eventHub.yield(.authenticated(pending.macID))
        eventHub.yield(.catalog(pending.macID, pending.catalog.revision, pending.catalog.controls))
        try? await persistence.saveCatalog(pending.macID, pending.catalog.revision, pending.catalog.controls)
        pending.session.startReceiving()
        if let previousSession { await closeSession(previousSession) }
        if foregrounded == false { await setForegrounded(false) }
        finalizingTransactionID = nil
        return pending.mac
    }

    func abortPairing(_ transactionID: UUID?) async {
        guard let token = pairingToken else { return }
        if let transactionID {
            let matchesPreparing = preparingSession?.transactionID == transactionID
            let matchesPrepared = pendingPreparedSession?.transactionID == transactionID
            guard matchesPreparing || matchesPrepared else { return }
        }
        await abortPairing(token: token, transactionID: transactionID)
    }

    private func abortPairing(token: UUID, transactionID: UUID? = nil) async {
        guard pairingToken == token else { return }
        if let finalizingTransactionID,
           transactionID == nil || transactionID == finalizingTransactionID { return }
        pairingTask?.cancel()
        pairingTask = nil
        if let preparing = preparingSession, preparing.pairingToken == token {
            preparingSession = nil
            await preparing.session.abortPairing(preparing.transactionID)
            await closeSession(preparing.session)
            guard pairingToken == token else { return }
        }
        guard let pending = pendingPreparedSession, pending.pairingToken == token,
              transactionID == nil || transactionID == pending.transactionID else {
            if pairingToken == token { pairingToken = nil }
            return
        }
        var rollbackPending = pending
        if rollbackPending.candidateSessionNeedsClose {
            rollbackPending.candidateSessionNeedsClose = false
            pendingPreparedSession = rollbackPending
            await rollbackPending.session.abortPairing(rollbackPending.transactionID)
            await closeSession(rollbackPending.session)
        }
        let restored = await restorePreparedPairing(rollbackPending)
        guard pairingToken == token,
              pendingPreparedSession?.transactionID == pending.transactionID else { return }
        if restored {
            pendingPreparedSession = nil
            pairingToken = nil
        }
    }

    private func restorePreparedPairing(_ pending: PendingPreparedSession) async -> Bool {
        do {
            return try await localStateMutations.run { [keychain, persistence] in
                guard try await keychain.deleteProvisionalCredential(
                    pending.transactionID,
                    pending.persistenceRecord.candidateCredentialVerifier
                ) else { return false }
                try await persistence.restorePairingState(pending.persistenceRecord)
                return true
            }
        } catch {
            return false
        }
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

        generation &+= 1
        connectionTask?.cancel()
        pairingTask?.cancel()
        connectionTask = nil
        pairingTask = nil
        pairingToken = nil
        pendingRevocation = nil

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

    func subscribe(_ ids: Set<RemoteControlID>) async throws {
        guard let session else { throw RemoteProtocolError(code: .authenticationFailed, message: "Mac is offline") }
        try await session.subscribe(ids)
    }

    func send(_ invocation: RemoteActionInvocation) async throws -> RemoteActionResult {
        guard selected?.id == invocation.macID,
              sessionToken == invocation.sessionID,
              let session
        else { throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed") }
        let result = try await actionDeadline(actionTimeout) {
            try await session.send(invocation.request)
        }
        guard selected?.id == invocation.macID,
              sessionToken == invocation.sessionID,
              self.session === session else {
            throw RemoteProtocolError(code: .authenticationFailed, message: "The selected Mac session changed")
        }
        return result
    }

    func setForegrounded(_ value: Bool) async {
        foregroundLifecycleGeneration &+= 1
        let lifecycleGeneration = foregroundLifecycleGeneration
        foregrounded = value
        guard value else {
            if finalizingTransactionID != nil {
                generation &+= 1
                connectionTask?.cancel()
                connectionTask = nil
                let detachedSession = session
                session = nil
                sessionToken = nil
                browser?.cancel()
                browser = nil
                browserRetryTask?.cancel()
                browserRetryTask = nil
                browserGeneration &+= 1
                discovered.removeAll()
                if let detachedSession { await closeSession(detachedSession) }
                await backgroundCleanup()
                return
            }
            await abortPairing(nil)
            generation &+= 1
            connectionTask?.cancel()
            connectionTask = nil
            let detachedSession = session
            session = nil
            sessionToken = nil
            browser?.cancel()
            browser = nil
            browserRetryTask?.cancel()
            browserRetryTask = nil
            browserGeneration &+= 1
            discovered.removeAll()
            if let detachedSession { await closeSession(detachedSession) }
            await backgroundCleanup()
            guard foregroundLifecycleGeneration == lifecycleGeneration else { return }
            return
        }
        startDiscovery()
        guard foregroundLifecycleGeneration == lifecycleGeneration, foregrounded else { return }
        if let selected, session == nil { await select(selected) }
    }

    private func connectWithRetry(_ mac: PairedMac, generation expectedGeneration: UInt64) async {
        let delays: [Duration] = [.zero, .milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)]
        for delay in delays {
            guard Task.isCancelled == false, foregrounded, generation == expectedGeneration, selected?.id == mac.id else { return }
            do {
                if delay != .zero { try await Task.sleep(for: delay) }
                let candidates = Self.orderedCandidates(
                    Array((discovered[mac.id] ?? [:]).values),
                    preferredEndpointDescription: mac.lastEndpointDescription
                )
                if try await recoverPreparedPairingIfNeeded(
                    mac,
                    candidates: candidates,
                    expectedGeneration: expectedGeneration
                ) {
                    return
                }
                guard candidates.isEmpty == false else {
                    throw RemoteProtocolError(code: .requestTimedOut, message: "Mac was not found on the local network")
                }
                guard let credential = try await keychain.loadCredential(mac.id), credential.count == 32 else {
                    await markRequiresPairing(mac.id)
                    eventHub.yield(.offline(mac.id, "Pairing is required"))
                    return
                }
                eventHub.yield(.connecting(mac.id))
                let deviceID = self.deviceID
                var connectedSession: (RemoteClientSession, UUID, DiscoveredMac)?
                var candidateError: Swift.Error?
                for candidate in candidates {
                    guard Task.isCancelled == false, generation == expectedGeneration, selected?.id == mac.id, foregrounded else { return }
                    let newSessionToken = UUID()
                    do {
                        let connected = try await Self.withTimeout(.seconds(15)) {
                            try await RemoteClientSession.authenticate(
                                endpoint: candidate.endpoint,
                                expectedMacID: mac.id,
                                credential: credential,
                                deviceID: deviceID,
                                deviceName: RemoteDeviceIdentity.name,
                                sessionToken: newSessionToken,
                                event: { [weak self] message in
                                    await self?.handle(message, macID: mac.id, sessionToken: newSessionToken)
                                },
                                disconnected: { [weak self] error in
                                    await self?.sessionDisconnected(
                                        macID: mac.id,
                                        sessionToken: newSessionToken,
                                        error: error
                                    )
                                }
                            )
                        }
                        connectedSession = (connected, newSessionToken, candidate)
                        break
                    } catch is RemoteClientSession.AuthenticatedCredentialRevocation {
                        guard generation == expectedGeneration,
                              selected?.id == mac.id,
                              foregrounded else { return }
                        let revocation = beginRevocation(
                            macID: mac.id,
                            credential: credential,
                            generation: expectedGeneration,
                            authenticatedSessionToken: newSessionToken,
                            source: .offline
                        )
                        await commitRevocation(revocation)
                        return
                    } catch {
                        candidateError = error
                    }
                }
                guard let (connected, newSessionToken, authenticatedCandidate) = connectedSession else {
                    throw candidateError ?? RemoteProtocolError(code: .requestTimedOut, message: "No reachable Mac candidate")
                }
                guard generation == expectedGeneration, selected?.id == mac.id, foregrounded else {
                    await connected.close()
                    return
                }
                session = connected
                sessionToken = newSessionToken
                selected?.lastEndpointDescription = String(describing: authenticatedCandidate.endpoint)
                selected?.lastConnectedAt = .now
                try? await persistence.updateEndpoint(
                    mac.id,
                    selected?.lastEndpointDescription,
                    selected?.lastConnectedAt
                )
                eventHub.yield(.sessionStarted(mac.id, newSessionToken))
                eventHub.yield(.authenticated(mac.id))
                connected.startReceiving()
                do {
                    try await catalogRequest(connected)
                } catch {
                    await connected.close()
                    if Self.shouldClearSession(currentToken: sessionToken, failedToken: newSessionToken) {
                        session = nil
                        sessionToken = nil
                    }
                    throw error
                }
                return
            } catch is CancellationError {
                return
            } catch {
                guard generation == expectedGeneration, selected?.id == mac.id, foregrounded else { return }
                eventHub.yield(.offline(mac.id, Self.safeMessage(error)))
            }
        }
    }

    private func recoverPreparedPairingIfNeeded(
        _ mac: PairedMac,
        candidates: [DiscoveredMac],
        expectedGeneration: UInt64
    ) async throws -> Bool {
        guard let record = try await persistence.loadPreparedPairingState(),
              record.candidate.id == mac.id else { return false }

        let provisional = try await keychain.loadProvisionalCredential(record.transactionID)
        let committed = try await keychain.loadCredential(mac.id)
        let credential = [provisional, committed]
            .compactMap { $0 }
            .first { RemoteKeychainClient.credentialVerifier($0) == record.candidateCredentialVerifier }

        guard let credential else {
            guard record.phase == .prepared else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing recovery credential is unavailable")
            }
            try await restorePersistedPreparedPairing(record)
            installPreviousSelection(from: record, expectedGeneration: expectedGeneration)
            return true
        }

        var lastError: Swift.Error?
        for candidate in candidates {
            guard generation == expectedGeneration,
                  selected?.id == mac.id,
                  foregrounded,
                  Task.isCancelled == false else { throw CancellationError() }
            let recoveryToken = UUID()
            do {
                let recovered = try await Self.withTimeout(.seconds(15)) {
                    try await RemoteClientSession.authenticate(
                        endpoint: candidate.endpoint,
                        expectedMacID: mac.id,
                        credential: credential,
                        deviceID: self.deviceID,
                        deviceName: RemoteDeviceIdentity.name,
                        sessionToken: recoveryToken,
                        event: { [weak self] message in
                            await self?.handle(message, macID: mac.id, sessionToken: recoveryToken)
                        },
                        disconnected: { [weak self] error in
                            await self?.sessionDisconnected(macID: mac.id, sessionToken: recoveryToken, error: error)
                        }
                    )
                }
                if record.phase == .prepared {
                    await recovered.abortPairing(record.transactionID)
                    await closeSession(recovered)
                    try await restorePersistedPreparedPairing(record)
                    installPreviousSelection(from: record, expectedGeneration: expectedGeneration)
                    return true
                }

                finalizingTransactionID = record.transactionID
                let state = try await Self.withTimeout(.seconds(10)) {
                    try await recovered.resolvePairing(record.transactionID)
                }
                guard state == .committed else {
                    await closeSession(recovered)
                    throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing recovery was not committed")
                }
                let catalog = try await Self.withTimeout(.seconds(10)) { try await recovered.receiveCatalog() }
                try Self.validateCatalog(catalog, minimumRevision: 0)
                try await localStateMutations.run { [keychain, persistence] in
                    guard try await keychain.promoteProvisionalCredential(
                        record.transactionID,
                        mac.id,
                        record.candidateCredentialVerifier
                    ) else {
                        throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing credential ownership changed")
                    }
                    try await persistence.finalizePairingState(record.transactionID)
                }
                guard generation == expectedGeneration,
                      selected?.id == mac.id,
                      foregrounded else {
                    await closeSession(recovered)
                    throw CancellationError()
                }
                session = recovered
                sessionToken = recoveryToken
                selected = record.candidate
                selected?.lastEndpointDescription = String(describing: candidate.endpoint)
                selected?.lastConnectedAt = .now
                eventHub.yield(.sessionStarted(mac.id, recoveryToken))
                eventHub.yield(.authenticated(mac.id))
                eventHub.yield(.catalog(mac.id, catalog.revision, catalog.controls))
                try? await persistence.saveCatalog(mac.id, catalog.revision, catalog.controls)
                recovered.startReceiving()
                finalizingTransactionID = nil
                return true
            } catch {
                lastError = error
            }
        }
        if record.phase == .prepared {
            try await restorePersistedPreparedPairing(record)
            installPreviousSelection(from: record, expectedGeneration: expectedGeneration)
            return true
        }
        throw lastError ?? RemoteProtocolError(code: .requestTimedOut, message: "Pairing recovery Mac was unreachable")
    }

    private func restorePersistedPreparedPairing(_ record: PreparedPairingPersistenceRecord) async throws {
        try await localStateMutations.run { [keychain, persistence] in
            guard try await keychain.deleteProvisionalCredential(
                record.transactionID,
                record.candidateCredentialVerifier
            ) else {
                throw RemoteProtocolError(code: .authenticationFailed, message: "Pairing credential ownership changed")
            }
            try await persistence.restorePairingState(record)
        }
    }

    private func installPreviousSelection(
        from record: PreparedPairingPersistenceRecord,
        expectedGeneration: UInt64
    ) {
        if generation == expectedGeneration {
            selected = record.previous.pairedMacs.first { $0.id == record.previous.selectedMacID }
        }
        eventHub.yield(.persistenceRestored)
    }

    private func replaceSession(_ newSession: RemoteClientSession, token: UUID, selectedMac: PairedMac) async {
        connectionTask?.cancel()
        connectionTask = nil
        if let session { await session.close() }
        session = newSession
        sessionToken = token
        selected = selectedMac
    }

    private func handle(_ message: RemoteMessage, macID: UUID, sessionToken token: UUID) async {
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

    private func sessionDisconnected(macID: UUID, sessionToken token: UUID, error: Swift.Error) async {
        guard foregrounded, Self.isCurrentSession(
            selectedMacID: selected?.id,
            currentToken: sessionToken,
            eventMacID: macID,
            eventToken: token
        ) else { return }
        eventHub.yield(.offline(macID, Self.safeMessage(error)))
        if let selected { await select(selected) }
    }

    private func markRequiresPairing(_ id: UUID) async {
        try? await persistence.updateRequiresPairing(id, true)
    }

    private func beginRevocation(
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

    private func commitRevocation(_ revocation: PendingRevocation) async {
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

    private func updateDiscovery(_ results: Set<NWBrowser.Result>) async {
        var candidates: [DiscoveredMac] = []
        for result in results {
            guard case let .bonjour(txtRecord) = result.metadata,
                  let idString = txtRecord["id"],
                  let id = UUID(uuidString: idString),
                  let majorString = txtRecord["version"],
                  let major = UInt16(majorString) else { continue }
            let minor = txtRecord["minor"].flatMap(UInt16.init) ?? 0
            let name: String
            if case let .service(serviceName, _, _, _) = result.endpoint { name = serviceName }
            else { name = id.uuidString }
            let mac = DiscoveredMac(
                id: id,
                displayName: name,
                endpoint: result.endpoint,
                protocolVersion: .init(major: major, minor: minor)
            )
            candidates.append(mac)
        }
        let preferred = selected.flatMap { selected in
            selected.lastEndpointDescription.map { [selected.id: $0] }
        } ?? [:]
        let updated = Self.boundedCandidates(
            candidates,
            preferredEndpoints: preferred,
            selectedMacID: selected?.id
        )
        for (id, candidates) in updated {
            let primary = candidates.values.sorted { String(describing: $0.endpoint) < String(describing: $1.endpoint) }.first
            let oldPrimary = discovered[id]?.values.sorted { String(describing: $0.endpoint) < String(describing: $1.endpoint) }.first
            if let primary, primary != oldPrimary { discoveryHub.yield(.added(primary)) }
        }
        for id in discovered.keys where updated[id] == nil { discoveryHub.yield(.removed(id)) }
        let selectedCandidatesChanged = selected.map {
            Self.candidateSetChanged(
                previous: discovered[$0.id] ?? [:],
                updated: updated[$0.id] ?? [:]
            )
        } ?? false
        discovered = updated
        if selectedCandidatesChanged, let selected, updated[selected.id]?.isEmpty == false, session == nil {
            await select(selected)
        }
    }

    private func browserBecameReady() {
        browserFailureCount = 0
        browserRetryTask?.cancel()
        browserRetryTask = nil
    }

    private func stopDiscoveryIfUnused() {
        guard discoveryHub.subscriberCount == 0 else { return }
        browser?.cancel()
        browser = nil
        browserRetryTask?.cancel()
        browserRetryTask = nil
        browserGeneration &+= 1
        discovered.removeAll()
    }

    private func scheduleBrowserRestart() {
        browser?.cancel()
        browser = nil
        browserRetryTask?.cancel()
        browserGeneration &+= 1
        let expectedGeneration = browserGeneration
        guard foregrounded else { return }
        let delay = Self.browserRetryDelay(failureCount: browserFailureCount)
        browserFailureCount = min(browserFailureCount + 1, 4)
        browserRetryTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) }
            catch { return }
            await self?.restartBrowser(generation: expectedGeneration)
        }
    }

    private func restartBrowser(generation expectedGeneration: UInt64) {
        guard foregrounded, browserGeneration == expectedGeneration else { return }
        browserRetryTask = nil
        startDiscovery()
    }

    private static func validatedDeviceName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.utf8.count <= 128,
              trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Invalid device name")
        }
        return trimmed
    }

    static func validateCatalog(_ catalog: RemoteCatalogCache, minimumRevision: UInt64) throws {
        guard catalog.revision >= minimumRevision,
              catalog.controls.count <= 4_096,
              Set(catalog.controls.map(\.id)).count == catalog.controls.count else {
            throw RemoteProtocolError(code: .invalidFrame, message: "Invalid catalog snapshot")
        }
        for descriptor in catalog.controls {
            guard descriptor.id.value.isEmpty == false,
                  descriptor.id.value.utf8.count <= 512,
                  descriptor.title.isEmpty == false,
                  descriptor.title.utf8.count <= 512,
                  (descriptor.unavailableReason?.utf8.count ?? 0) <= 1_024 else {
                throw RemoteProtocolError(code: .invalidFrame, message: "Invalid catalog descriptor")
            }
            switch descriptor.icon {
            case let .systemSymbol(name):
                guard name.isEmpty == false, name.utf8.count <= 256 else {
                    throw RemoteProtocolError(code: .invalidFrame, message: "Invalid catalog icon")
                }
            case let .png(data):
                guard data.count <= 256 * 1_024 else {
                    throw RemoteProtocolError(code: .invalidFrame, message: "Catalog icon exceeds 256 KiB")
                }
            }
        }
    }

    static func orderedCandidates(
        _ candidates: [DiscoveredMac],
        preferredEndpointDescription: String? = nil
    ) -> [DiscoveredMac] {
        candidates.sorted { lhs, rhs in
            let left = String(describing: lhs.endpoint)
            let right = String(describing: rhs.endpoint)
            if left == preferredEndpointDescription { return right != preferredEndpointDescription }
            if right == preferredEndpointDescription { return false }
            return left < right
        }
    }

    static func boundedCandidates(
        _ candidates: [DiscoveredMac],
        preferredEndpoints: [UUID: String] = [:],
        selectedMacID: UUID? = nil
    ) -> [UUID: [String: DiscoveredMac]] {
        let grouped = Dictionary(grouping: candidates, by: \.id)
        var queues: [UUID: [(String, DiscoveredMac)]] = [:]
        for id in grouped.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let preferred = preferredEndpoints[id]
            var unique: [String: DiscoveredMac] = [:]
            for candidate in orderedCandidates(grouped[id] ?? [], preferredEndpointDescription: preferred) {
                unique[String(describing: candidate.endpoint)] = candidate
            }
            queues[id] = orderedCandidates(Array(unique.values), preferredEndpointDescription: preferred)
                .prefix(maximumCandidatesPerMac)
                .map { (String(describing: $0.endpoint), $0) }
        }
        var result: [UUID: [String: DiscoveredMac]] = [:]
        var remainingCapacity = maximumCandidatesGlobally
        if let selectedMacID, let selectedQueue = queues[selectedMacID] {
            for (description, candidate) in selectedQueue.prefix(remainingCapacity) {
                result[selectedMacID, default: [:]][description] = candidate
                remainingCapacity -= 1
            }
            queues[selectedMacID] = []
        }
        let ids = queues.keys.sorted { $0.uuidString < $1.uuidString }
        var rank = 0
        while remainingCapacity > 0 {
            var inserted = false
            for id in ids where remainingCapacity > 0 {
                guard let queue = queues[id], rank < queue.count else { continue }
                let (description, candidate) = queue[rank]
                result[id, default: [:]][description] = candidate
                remainingCapacity -= 1
                inserted = true
            }
            guard inserted else { break }
            rank += 1
        }
        return result
    }

    static func candidateSetChanged(
        previous: [String: DiscoveredMac],
        updated: [String: DiscoveredMac]
    ) -> Bool {
        Set(previous.keys) != Set(updated.keys)
    }

    func installDiscoveredCandidatesForTesting(_ candidates: [DiscoveredMac]) {
        discovered = Self.boundedCandidates(
            candidates,
            selectedMacID: selected?.id
        )
    }

    var lifecycleSnapshot: (foregrounded: Bool, ownsBrowser: Bool, hasConnectionTask: Bool, hasRetryTask: Bool) {
        (foregrounded, browser != nil, connectionTask != nil, browserRetryTask != nil)
    }

    static func isCurrentSession(
        selectedMacID: UUID?,
        currentToken: UUID?,
        eventMacID: UUID,
        eventToken: UUID
    ) -> Bool {
        selectedMacID == eventMacID && currentToken == eventToken
    }

    static func shouldClearSession(currentToken: UUID?, failedToken: UUID) -> Bool {
        currentToken == failedToken
    }

    static func browserRetryDelay(failureCount: Int) -> Duration {
        let delays: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)]
        return delays[min(max(failureCount, 0), delays.count - 1)]
    }

    static func mayCommitPairing(
        activeToken: UUID?,
        candidateToken: UUID,
        currentGeneration: UInt64,
        expectedGeneration: UInt64,
        foregrounded: Bool
    ) -> Bool {
        foregrounded && activeToken == candidateToken && currentGeneration == expectedGeneration
    }

    static func isAuthoritativeRevocation(_ message: RemoteMessage) -> Bool {
        message == .credentialRevoked
    }

    private static func safeMessage(_ error: Swift.Error) -> String? {
        if let error = error as? RemoteProtocolError { return error.message }
        return "Unable to connect to this Mac"
    }


    private static func withTimeout<Value: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw RemoteProtocolError(code: .requestTimedOut, message: "The Mac did not respond in time")
            }
            guard let result = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return result
        }
    }
}

actor RemoteClientSession {
    struct AuthenticatedCredentialRevocation: Swift.Error, Sendable {}

    struct PairingResult: Sendable {
        let session: RemoteClientSession
        let credential: Data
        let transactionID: UUID
        let catalogRevision: UInt64
    }

    nonisolated let token: UUID
    nonisolated let credentialIdentity: Data
    private let io: RemoteConnectionIO
    private let crypto: RemoteSessionCrypto
    private let event: @Sendable (RemoteMessage) async -> Void
    private let disconnected: @Sendable (Swift.Error) async -> Void
    private let actionResponses = RemoteActionResponses()
    private var receiveTask: Task<Void, Never>?
    private var closed = false

    private init(
        io: RemoteConnectionIO,
        crypto: RemoteSessionCrypto,
        credentialIdentity: Data,
        token: UUID,
        event: @escaping @Sendable (RemoteMessage) async -> Void,
        disconnected: @escaping @Sendable (Swift.Error) async -> Void
    ) {
        self.token = token
        self.io = io
        self.crypto = crypto
        self.credentialIdentity = credentialIdentity
        self.event = event
        self.disconnected = disconnected
    }

    static func preparePairing(
        endpoint: NWEndpoint,
        expectedMacID: UUID,
        code: String,
        deviceID: UUID,
        deviceName: String,
        sessionToken: UUID = UUID(),
        event: @escaping @Sendable (RemoteMessage) async -> Void,
        disconnected: @escaping @Sendable (Swift.Error) async -> Void = { _ in }
    ) async throws -> PairingResult {
        let handshake = try await begin(endpoint: endpoint, expectedMacID: expectedMacID, deviceID: deviceID, deviceName: deviceName)
        do {
            try await handshake.io.send(.plaintext(.pairingRequest))
            let proof = try RemoteSessionCrypto.makePairingProof(
                privateKey: handshake.key,
                peerPublicKey: handshake.server.ephemeralPublicKey,
                pairingCode: code,
                transcript: handshake.transcript
            )
            try await handshake.io.send(.plaintext(.pairingProof(.init(deviceID: deviceID, proof: proof))))
            let pairingCrypto = try makeCrypto(credential: Data(code.utf8), handshake: handshake)
            let pairingMessage = try await receiveEncrypted(io: handshake.io, crypto: pairingCrypto)
            guard case let .pairingPrepared(prepared) = pairingMessage else { throw invalid("Pairing preparation required") }
            guard prepared.macID == expectedMacID,
                  prepared.credential.count == 32,
                  prepared.expiresAt > Date() else { throw invalid("Invalid pairing preparation") }
            let sessionCrypto = try makeCrypto(credential: prepared.credential, handshake: handshake)
            let authentication = AuthenticationProof(
                deviceID: deviceID,
                proof: RemoteHandshakeCrypto.authenticationProof(
                    credential: prepared.credential,
                    transcript: handshake.transcript
                )
            )
            try await handshake.io.send(.encrypted(try sessionCrypto.seal(.authenticationProof(authentication))))
            return PairingResult(
                session: Self(
                    io: handshake.io,
                    crypto: sessionCrypto,
                    credentialIdentity: prepared.credential,
                    token: sessionToken,
                    event: event,
                    disconnected: disconnected
                ),
                credential: prepared.credential,
                transactionID: prepared.transactionID,
                catalogRevision: prepared.catalogRevision
            )
        } catch {
            await handshake.io.cancel()
            throw error
        }
    }

    static func authenticate(
        endpoint: NWEndpoint,
        expectedMacID: UUID,
        credential: Data,
        deviceID: UUID,
        deviceName: String,
        sessionToken: UUID = UUID(),
        event: @escaping @Sendable (RemoteMessage) async -> Void,
        disconnected: @escaping @Sendable (Swift.Error) async -> Void = { _ in }
    ) async throws -> RemoteClientSession {
        guard credential.count == 32 else { throw RemoteKeychainClient.Error.invalidCredentialLength }
        let handshake = try await begin(endpoint: endpoint, expectedMacID: expectedMacID, deviceID: deviceID, deviceName: deviceName)
        do {
            let crypto = try makeCrypto(credential: credential, handshake: handshake)
            let proof = AuthenticationProof(
                deviceID: deviceID,
                proof: RemoteHandshakeCrypto.authenticationProof(
                    credential: credential,
                    transcript: handshake.transcript
                )
            )
            try await handshake.io.send(.encrypted(try crypto.seal(.authenticationProof(proof))))
            let response = try await handshake.io.receive()
            if case let .credentialRevocationProof(revocation)? = response.plaintext {
                let verifier = RemoteHandshakeCrypto.revocationVerifier(credential: credential)
                guard handshake.server.version.supportsAuthenticatedRevocation,
                      revocation.deviceID == deviceID,
                      RemoteHandshakeCrypto.verifyRevocationProof(
                          revocation.proof,
                          verifier: verifier,
                          transcript: handshake.transcript
                      ) else {
                    throw RemoteProtocolError(code: .authenticationFailed, message: "Invalid revocation proof")
                }
                throw AuthenticatedCredentialRevocation()
            }
            guard response.kind == .encrypted,
                  let frame = response.encrypted,
                  case let .authenticationResult(result) = try crypto.open(frame) else {
                throw invalid("Authentication result required")
            }
            _ = try result.get()
            return Self(
                io: handshake.io,
                crypto: crypto,
                credentialIdentity: credential,
                token: sessionToken,
                event: event,
                disconnected: disconnected
            )
        } catch {
            await handshake.io.cancel()
            throw error
        }
    }

    nonisolated func startReceiving() {
        Task { await self.startReceiveLoopIfNeeded() }
    }

    func requestCatalog() async throws { try await sendMessage(.catalogRequest) }
    func receiveCatalog() async throws -> RemoteCatalogCache {
        try await sendMessage(.catalogRequest)
        guard case let .catalogSnapshot(revision, controls) = try await receiveMessage() else {
            throw Self.invalid("Catalog snapshot required")
        }
        return .init(revision: revision, controls: controls)
    }

    func commitPairing(_ transactionID: UUID) async throws -> PairingTransactionState {
        let command = PairingTransactionCommand(transactionID: transactionID)
        try await sendMessage(.pairingCommit(command))
        let response = try await receiveMessage()
        if response == .pairingCommitted(command) { return .committed }
        if case let .pairingStatus(status) = response, status.transactionID == transactionID { return status.state }
        throw Self.invalid("Pairing confirmation required")
    }

    func resolvePairing(_ transactionID: UUID) async throws -> PairingTransactionState {
        try await sendMessage(.pairingStatusRequest(.init(transactionID: transactionID)))
        guard case let .pairingStatus(status) = try await receiveMessage(),
              status.transactionID == transactionID else { throw Self.invalid("Pairing status required") }
        if status.state == .prepared { return try await commitPairing(transactionID) }
        return status.state
    }

    func abortPairing(_ transactionID: UUID) async {
        try? await sendMessage(.pairingAbort(.init(transactionID: transactionID)))
    }
    func subscribe(_ ids: Set<RemoteControlID>) async throws { try await sendMessage(.subscriptionUpdate(ids)) }

    func send(_ request: RemoteActionRequest) async throws -> RemoteActionResult {
        let stream = await actionResponses.register(request.requestID)
        do {
            try await sendMessage(.actionRequest(request))
            for try await result in stream { return result }
            throw CancellationError()
        } catch {
            await actionResponses.cancel(request.requestID)
            throw error
        }
    }

    func close() async {
        guard closed == false else { return }
        closed = true
        receiveTask?.cancel()
        receiveTask = nil
        await io.cancel()
        await actionResponses.finishAll()
    }

    private func startReceiveLoopIfNeeded() {
        guard receiveTask == nil, closed == false else { return }
        receiveTask = Task { [weak self] in await self?.receiveLoop() }
    }

    private func receiveLoop() async {
        do {
            while Task.isCancelled == false {
                let message = try await receiveMessage()
                if case let .actionResult(result) = message { await actionResponses.resolve(result) }
                await event(message)
            }
        } catch is CancellationError {
        } catch {
            await actionResponses.finishAll()
            await disconnected(error)
        }
    }

    private func sendMessage(_ message: RemoteMessage) async throws {
        guard closed == false else { throw CancellationError() }
        try await io.send(.encrypted(try crypto.seal(message)))
    }

    private func receiveMessage() async throws -> RemoteMessage {
        try await Self.receiveEncrypted(io: io, crypto: crypto)
    }

    private struct Handshake: Sendable {
        let io: RemoteConnectionIO
        let key: P256.KeyAgreement.PrivateKey
        let server: ServerHello
        let transcript: Data
    }

    private static func begin(endpoint: NWEndpoint, expectedMacID: UUID, deviceID: UUID, deviceName: String) async throws -> Handshake {
        let io = RemoteConnectionIO(connection: NWConnection(to: endpoint, using: .tcp))
        do {
            try await io.start()
            let key = P256.KeyAgreement.PrivateKey()
            let hello = ClientHello(version: .current, deviceID: deviceID, deviceName: deviceName, ephemeralPublicKey: key.publicKey.rawRepresentation)
            try await io.send(.plaintext(.clientHello(hello)))
            let response = try await io.receive()
            if case let .sessionError(error)? = response.plaintext { throw error }
            guard response.kind == .plaintext,
                  case let .serverHello(server)? = response.plaintext,
                  server.macID == expectedMacID,
                  RemoteProtocolVersion.current.negotiated(with: server.version) == server.version,
                  server.challenge.count == 32 else { throw invalid("Invalid server hello") }
            return Handshake(io: io, key: key, server: server, transcript: try RemoteHandshakeCrypto.transcript(client: hello, server: server))
        } catch {
            await io.cancel()
            throw error
        }
    }

    private static func authenticate(io: RemoteConnectionIO, crypto: RemoteSessionCrypto, credential: Data, transcript: Data, deviceID: UUID) async throws {
        let proof = AuthenticationProof(deviceID: deviceID, proof: RemoteHandshakeCrypto.authenticationProof(credential: credential, transcript: transcript))
        try await io.send(.encrypted(try crypto.seal(.authenticationProof(proof))))
        guard case let .authenticationResult(result) = try await receiveEncrypted(io: io, crypto: crypto) else { throw invalid("Authentication result required") }
        _ = try result.get()
    }

    private static func makeCrypto(credential: Data, handshake: Handshake) throws -> RemoteSessionCrypto {
        let keys = try RemoteSessionCrypto.deriveSessionKeys(role: .client, privateKey: handshake.key, peerPublicKey: handshake.server.ephemeralPublicKey, credential: credential, transcript: handshake.transcript)
        return RemoteSessionCrypto(sendKey: keys.send, receiveKey: keys.receive, noncePrefix: UInt32.random(in: .min ... .max))
    }

    private static func receiveEncrypted(io: RemoteConnectionIO, crypto: RemoteSessionCrypto) async throws -> RemoteMessage {
        let packet = try await io.receive()
        guard packet.kind == .encrypted, let frame = packet.encrypted else { throw invalid("Encrypted packet required") }
        return try crypto.open(frame)
    }

    private static func invalid(_ message: String) -> RemoteProtocolError {
        .init(code: .invalidFrame, message: message)
    }
}

private actor RemoteActionResponses {
    typealias Stream = AsyncThrowingStream<RemoteActionResult, Swift.Error>
    private var continuations: [UUID: Stream.Continuation] = [:]

    func register(_ id: UUID) -> Stream {
        let (stream, continuation) = Stream.makeStream(of: RemoteActionResult.self, bufferingPolicy: .bufferingNewest(1))
        continuations[id]?.finish(throwing: CancellationError())
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.cancel(id) } }
        return stream
    }

    func resolve(_ result: RemoteActionResult) {
        guard let continuation = continuations.removeValue(forKey: result.requestID) else { return }
        continuation.yield(result)
        continuation.finish()
    }

    func cancel(_ id: UUID) { continuations.removeValue(forKey: id)?.finish(throwing: CancellationError()) }

    func finishAll() {
        let values = continuations.values
        continuations.removeAll()
        for continuation in values { continuation.finish(throwing: CancellationError()) }
    }
}

private enum RemoteDeviceIdentity {
    static let key = "remoteDeviceID"
    static var name: String { ProcessInfo.processInfo.hostName }

    static func load() -> UUID {
        if let value = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) { return value }
        let value = UUID()
        UserDefaults.standard.set(value.uuidString, forKey: key)
        return value
    }
}
