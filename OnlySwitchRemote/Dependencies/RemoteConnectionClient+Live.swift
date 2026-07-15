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
            pair: { try await runtime.pair($0, code: $1, deviceName: $2) },
            select: { await runtime.select($0) },
            events: { runtime.makeConnectionEventStream() },
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

actor RemoteConnectionRuntime {
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
    private var connectionTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var pendingPairedMacMetadata: [UUID: PairedMac] = [:]
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
        closeSession: @escaping @Sendable (RemoteClientSession) async -> Void = { await $0.close() }
    ) {
        self.persistence = persistence
        self.keychain = keychain
        self.deviceID = deviceID
        self.backgroundCleanup = backgroundCleanup
        self.catalogRequest = catalogRequest
        self.closeSession = closeSession
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

    func pair(_ mac: DiscoveredMac, code: String, deviceName: String) async throws -> PairedMac {
        guard mac.protocolVersion.isCompatible(with: .current) else {
            throw RemoteProtocolError(code: .upgradeRequired, message: "This Mac requires a compatible OnlySwitch version")
        }
        let cleanName = try Self.validatedDeviceName(deviceName)
        let deviceID = self.deviceID
        generation &+= 1
        let expectedGeneration = generation
        connectionTask?.cancel()
        connectionTask = nil
        pairingTask?.cancel()
        let priorSession = session
        session = nil
        sessionToken = nil
        selected = nil
        let pairingToken = UUID()
        self.pairingToken = pairingToken
        if let priorSession { await closeSession(priorSession) }
        guard Self.mayCommitPairing(activeToken: self.pairingToken, candidateToken: pairingToken, currentGeneration: generation, expectedGeneration: expectedGeneration, foregrounded: foregrounded) else {
            throw CancellationError()
        }
        let newSessionToken = UUID()
        let task = Task {
            try await Self.withTimeout(.seconds(15)) {
                try await RemoteClientSession.pair(
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
            result = try await task.value
        } catch {
            if self.pairingToken == pairingToken {
                pairingTask = nil
                self.pairingToken = nil
            }
            throw error
        }
        guard result.credential.count == 32 else {
            await result.session.close()
            throw RemoteKeychainClient.Error.invalidCredentialLength
        }
        do {
            try await saveCredentialAfterRemoteCommit(mac.id, credential: result.credential)
        } catch {
            await result.session.close()
            if self.pairingToken == pairingToken {
                pairingTask = nil
                self.pairingToken = nil
            }
            throw error
        }
        let value = PairedMac(
            id: mac.id,
            displayName: mac.displayName,
            lastEndpointDescription: String(describing: mac.endpoint),
            lastConnectedAt: .now,
            requiresPairing: false
        )
        pendingPairedMacMetadata[mac.id] = value
        var metadataError: Swift.Error?
        do {
            try await persistence.upsertPairedMac(value)
            pendingPairedMacMetadata[mac.id] = nil
        } catch {
            metadataError = error
        }
        guard Self.mayCommitPairing(
            activeToken: self.pairingToken,
            candidateToken: pairingToken,
            currentGeneration: generation,
            expectedGeneration: expectedGeneration,
            foregrounded: foregrounded
        ) else {
            await result.session.close()
            if self.pairingToken == pairingToken {
                pairingTask = nil
                self.pairingToken = nil
            }
            if let metadataError { throw metadataError }
            throw CancellationError()
        }
        pairingTask = nil
        self.pairingToken = nil
        await replaceSession(result.session, token: newSessionToken, selectedMac: value)
        eventHub.yield(.authenticated(mac.id))
        result.session.startReceiving()
        do {
            try await catalogRequest(result.session)
        } catch {
            await result.session.close()
            if Self.shouldClearSession(currentToken: sessionToken, failedToken: newSessionToken) {
                eventHub.yield(.offline(mac.id, Self.safeMessage(error)))
                session = nil
                sessionToken = nil
            }
        }
        if let metadataError { throw metadataError }
        return value
    }

    func select(_ mac: PairedMac?) async {
        generation &+= 1
        let currentGeneration = generation
        connectionTask?.cancel()
        pairingTask?.cancel()
        pairingTask = nil
        pairingToken = nil
        connectionTask = nil
        let previousSession = session
        session = nil
        sessionToken = nil
        selected = mac
        if let previousSession { await closeSession(previousSession) }
        guard generation == currentGeneration, selected?.id == mac?.id else { return }
        guard let mac, foregrounded else { return }
        connectionTask = Task { [weak self] in
            await self?.connectWithRetry(mac, generation: currentGeneration)
        }
    }

    func subscribe(_ ids: Set<RemoteControlID>) async throws {
        guard let session else { throw RemoteProtocolError(code: .authenticationFailed, message: "Mac is offline") }
        try await session.subscribe(ids)
    }

    func send(_ request: RemoteActionRequest) async throws -> RemoteActionResult {
        guard let session else { throw RemoteProtocolError(code: .authenticationFailed, message: "Mac is offline") }
        return try await session.send(request)
    }

    func setForegrounded(_ value: Bool) async {
        foregroundLifecycleGeneration &+= 1
        let lifecycleGeneration = foregroundLifecycleGeneration
        foregrounded = value
        guard value else {
            generation &+= 1
            connectionTask?.cancel()
            pairingTask?.cancel()
            connectionTask = nil
            pairingTask = nil
            pairingToken = nil
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
        await retryPendingMetadata()
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
                        if (try? await keychain.deleteCredentialIfMatches(mac.id, credential)) == true {
                            try? await persistence.updateRequiresPairing(mac.id, true)
                            eventHub.yield(.revoked(mac.id))
                        }
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

    private func replaceSession(_ newSession: RemoteClientSession, token: UUID, selectedMac: PairedMac) async {
        generation &+= 1
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
            pairingTask?.cancel()
            connectionTask = nil
            pairingTask = nil
            pairingToken = nil
            session = nil
            sessionToken = nil
            if let revokedSession { await closeSession(revokedSession) }
            guard let revokedCredential,
                  (try? await keychain.deleteCredentialIfMatches(macID, revokedCredential)) == true else { return }
            try? await persistence.updateRequiresPairing(macID, true)
            guard generation == revocationGeneration, session == nil, selected?.id == macID else { return }
            eventHub.yield(.revoked(macID))
            return
        }
        switch message {
        case let .catalogSnapshot(revision, controls):
            try? await persistence.saveCatalog(macID, revision, controls)
            eventHub.yield(.catalog(macID, revision, controls))
        case let .statusSnapshot(statuses):
            try? await persistence.saveStatuses(macID, statuses)
            for status in statuses { eventHub.yield(.status(macID, status)) }
        case let .statusChanged(status):
            try? await persistence.mergeStatus(macID, status)
            eventHub.yield(.status(macID, status))
        case let .actionResult(result):
            eventHub.yield(.action(macID, result))
        case let .catalogChanged(revision):
            eventHub.yield(.catalog(macID, revision, []))
            try? await session?.requestCatalog()
        default:
            break
        }
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

    private func saveCredentialAfterRemoteCommit(_ id: UUID, credential: Data) async throws {
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

    private func retryPendingMetadata() async {
        for (id, value) in pendingPairedMacMetadata {
            if (try? await persistence.upsertPairedMac(value)) != nil {
                pendingPairedMacMetadata[id] = nil
            }
        }
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
        let updated = Self.boundedCandidates(candidates, preferredEndpoints: preferred)
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
        preferredEndpoints: [UUID: String] = [:]
    ) -> [UUID: [String: DiscoveredMac]] {
        let grouped = Dictionary(grouping: candidates, by: \.id)
        var bounded: [(UUID, String, DiscoveredMac, Bool)] = []
        for id in grouped.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let preferred = preferredEndpoints[id]
            for candidate in orderedCandidates(grouped[id] ?? [], preferredEndpointDescription: preferred)
                .prefix(maximumCandidatesPerMac) {
                let description = String(describing: candidate.endpoint)
                bounded.append((id, description, candidate, description == preferred))
            }
        }
        bounded.sort { lhs, rhs in
            if lhs.3 != rhs.3 { return lhs.3 && !rhs.3 }
            if lhs.0 != rhs.0 { return lhs.0.uuidString < rhs.0.uuidString }
            return lhs.1 < rhs.1
        }
        var result: [UUID: [String: DiscoveredMac]] = [:]
        for (id, description, candidate, _) in bounded.prefix(maximumCandidatesGlobally) {
            result[id, default: [:]][description] = candidate
        }
        return result
    }

    static func candidateSetChanged(
        previous: [String: DiscoveredMac],
        updated: [String: DiscoveredMac]
    ) -> Bool {
        Set(previous.keys) != Set(updated.keys)
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

    static func pair(
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
            guard case let .pairingResult(result) = pairingMessage else { throw invalid("Pairing result required") }
            let success = try result.get()
            guard success.macID == expectedMacID, success.credential.count == 32 else { throw invalid("Invalid pairing credential") }
            let sessionCrypto = try makeCrypto(credential: success.credential, handshake: handshake)
            try await authenticate(io: handshake.io, crypto: sessionCrypto, credential: success.credential, transcript: handshake.transcript, deviceID: deviceID)
            return PairingResult(
                session: Self(
                    io: handshake.io,
                    crypto: sessionCrypto,
                    credentialIdentity: success.credential,
                    token: sessionToken,
                    event: event,
                    disconnected: disconnected
                ),
                credential: success.credential
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
                  server.version.isCompatible(with: .current),
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
