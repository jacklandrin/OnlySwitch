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
            discover: {
                let stream = runtime.discoveryStream
                Task { await runtime.startDiscovery() }
                return stream
            },
            pair: { try await runtime.pair($0, code: $1, deviceName: $2) },
            select: { await runtime.select($0) },
            events: { runtime.connectionEvents },
            subscribe: { try await runtime.subscribe($0) },
            send: { try await runtime.send($0) },
            setForegrounded: { await runtime.setForegrounded($0) }
        )
    }
}

actor RemoteConnectionRuntime {
    nonisolated let discoveryStream: AsyncStream<DiscoveryEvent>
    nonisolated let connectionEvents: AsyncStream<RemoteConnectionEvent>

    private let discoveryContinuation: AsyncStream<DiscoveryEvent>.Continuation
    private let eventContinuation: AsyncStream<RemoteConnectionEvent>.Continuation
    private let persistence: RemotePersistenceClient
    private let keychain: RemoteKeychainClient
    private let deviceID: UUID
    private var browser: NWBrowser?
    private var discovered: [UUID: DiscoveredMac] = [:]
    private var selected: PairedMac?
    private var session: RemoteClientSession?
    private var connectionTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var foregrounded = true

    init(
        persistence: RemotePersistenceClient,
        keychain: RemoteKeychainClient,
        deviceID: UUID = RemoteDeviceIdentity.load()
    ) {
        self.persistence = persistence
        self.keychain = keychain
        self.deviceID = deviceID
        (discoveryStream, discoveryContinuation) = AsyncStream.makeStream(
            of: DiscoveryEvent.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        (connectionEvents, eventContinuation) = AsyncStream.makeStream(
            of: RemoteConnectionEvent.self,
            bufferingPolicy: .bufferingNewest(256)
        )
    }

    func startDiscovery() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_onlyswitch._tcp", domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { await self?.updateDiscovery(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { Task { await self?.restartDiscovery() } }
        }
        browser.start(queue: .global(qos: .userInitiated))
    }

    func pair(_ mac: DiscoveredMac, code: String, deviceName: String) async throws -> PairedMac {
        guard mac.protocolVersion.isCompatible(with: .current) else {
            throw RemoteProtocolError(code: .upgradeRequired, message: "This Mac requires a compatible OnlySwitch version")
        }
        let cleanName = try Self.validatedDeviceName(deviceName)
        let deviceID = self.deviceID
        let result = try await Self.withTimeout(.seconds(15)) {
            try await RemoteClientSession.pair(
                endpoint: mac.endpoint,
                expectedMacID: mac.id,
                code: code.uppercased(),
                deviceID: deviceID,
                deviceName: cleanName,
                event: { [weak self] message in await self?.handle(message, macID: mac.id) },
                disconnected: { [weak self] error in await self?.sessionDisconnected(macID: mac.id, error: error) }
            )
        }
        guard result.credential.count == 32 else {
            await result.session.close()
            throw RemoteKeychainClient.Error.invalidCredentialLength
        }
        do {
            try await keychain.saveCredential(mac.id, result.credential)
            var paired = try await persistence.loadPairedMacs()
            let value = PairedMac(
                id: mac.id,
                displayName: mac.displayName,
                lastEndpointDescription: String(describing: mac.endpoint),
                lastConnectedAt: .now,
                requiresPairing: false
            )
            paired.removeAll { $0.id == mac.id }
            paired.append(value)
            try await persistence.savePairedMacs(paired)
            await replaceSession(result.session, selectedMac: value)
            eventContinuation.yield(.authenticated(mac.id))
            result.session.startReceiving()
            try await result.session.requestCatalog()
            return value
        } catch {
            await result.session.close()
            try? await keychain.deleteCredential(mac.id)
            throw error
        }
    }

    func select(_ mac: PairedMac?) async {
        generation &+= 1
        let currentGeneration = generation
        connectionTask?.cancel()
        connectionTask = nil
        if let session { await session.close() }
        session = nil
        selected = mac
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
        foregrounded = value
        guard value else {
            generation &+= 1
            connectionTask?.cancel()
            connectionTask = nil
            if let session { await session.close() }
            session = nil
            return
        }
        if let selected, session == nil { await select(selected) }
    }

    private func connectWithRetry(_ mac: PairedMac, generation expectedGeneration: UInt64) async {
        let delays: [Duration] = [.zero, .milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)]
        for delay in delays {
            guard Task.isCancelled == false, foregrounded, generation == expectedGeneration, selected?.id == mac.id else { return }
            do {
                if delay != .zero { try await Task.sleep(for: delay) }
                guard let endpoint = discovered[mac.id]?.endpoint else {
                    throw RemoteProtocolError(code: .requestTimedOut, message: "Mac was not found on the local network")
                }
                guard let credential = try await keychain.loadCredential(mac.id), credential.count == 32 else {
                    eventContinuation.yield(.revoked(mac.id))
                    return
                }
                eventContinuation.yield(.connecting(mac.id))
                let deviceID = self.deviceID
                let connected = try await Self.withTimeout(.seconds(15)) {
                    try await RemoteClientSession.authenticate(
                        endpoint: endpoint,
                        expectedMacID: mac.id,
                        credential: credential,
                        deviceID: deviceID,
                        deviceName: RemoteDeviceIdentity.name,
                        event: { [weak self] message in await self?.handle(message, macID: mac.id) },
                        disconnected: { [weak self] error in await self?.sessionDisconnected(macID: mac.id, error: error) }
                    )
                }
                guard generation == expectedGeneration, selected?.id == mac.id, foregrounded else {
                    await connected.close()
                    return
                }
                session = connected
                eventContinuation.yield(.authenticated(mac.id))
                connected.startReceiving()
                try await connected.requestCatalog()
                return
            } catch is CancellationError {
                return
            } catch let error as RemoteProtocolError where error.code == .authenticationFailed {
                try? await keychain.deleteCredential(mac.id)
                eventContinuation.yield(.revoked(mac.id))
                return
            } catch {
                eventContinuation.yield(.offline(mac.id, Self.safeMessage(error)))
            }
        }
    }

    private func replaceSession(_ newSession: RemoteClientSession, selectedMac: PairedMac) async {
        generation &+= 1
        connectionTask?.cancel()
        connectionTask = nil
        if let session { await session.close() }
        session = newSession
        selected = selectedMac
    }

    private func handle(_ message: RemoteMessage, macID: UUID) async {
        guard selected?.id == macID else { return }
        switch message {
        case let .catalogSnapshot(revision, controls):
            try? await persistence.saveCatalog(macID, controls)
            eventContinuation.yield(.catalog(macID, revision, controls))
        case let .statusSnapshot(statuses):
            try? await persistence.saveStatuses(macID, statuses)
            for status in statuses { eventContinuation.yield(.status(macID, status)) }
        case let .statusChanged(status):
            eventContinuation.yield(.status(macID, status))
        case let .actionResult(result):
            eventContinuation.yield(.action(macID, result))
        case let .catalogChanged(revision):
            eventContinuation.yield(.catalog(macID, revision, []))
            try? await session?.requestCatalog()
        case let .sessionError(error) where error.code == .authenticationFailed:
            try? await keychain.deleteCredential(macID)
            eventContinuation.yield(.revoked(macID))
        default:
            break
        }
    }

    private func sessionDisconnected(macID: UUID, error: Swift.Error) async {
        guard foregrounded, selected?.id == macID else { return }
        if let error = error as? RemoteProtocolError, error.code == .authenticationFailed {
            try? await keychain.deleteCredential(macID)
            eventContinuation.yield(.revoked(macID))
            return
        }
        eventContinuation.yield(.offline(macID, Self.safeMessage(error)))
        if let selected { await select(selected) }
    }

    private func updateDiscovery(_ results: Set<NWBrowser.Result>) {
        var updated: [UUID: DiscoveredMac] = [:]
        for result in results {
            guard case let .bonjour(txtRecord) = result.metadata,
                  let idString = txtRecord["id"],
                  let id = UUID(uuidString: idString),
                  let majorString = txtRecord["version"],
                  let major = UInt16(majorString) else { continue }
            let name: String
            if case let .service(serviceName, _, _, _) = result.endpoint { name = serviceName }
            else { name = id.uuidString }
            updated[id] = DiscoveredMac(
                id: id,
                displayName: name,
                endpoint: result.endpoint,
                protocolVersion: .init(major: major, minor: 0)
            )
        }
        for (id, mac) in updated where discovered[id] != mac { discoveryContinuation.yield(.added(mac)) }
        for id in discovered.keys where updated[id] == nil { discoveryContinuation.yield(.removed(id)) }
        discovered = updated
    }

    private func restartDiscovery() {
        browser?.cancel()
        browser = nil
        guard foregrounded else { return }
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
    struct PairingResult: Sendable {
        let session: RemoteClientSession
        let credential: Data
    }

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
        event: @escaping @Sendable (RemoteMessage) async -> Void,
        disconnected: @escaping @Sendable (Swift.Error) async -> Void
    ) {
        self.io = io
        self.crypto = crypto
        self.event = event
        self.disconnected = disconnected
    }

    static func pair(
        endpoint: NWEndpoint,
        expectedMacID: UUID,
        code: String,
        deviceID: UUID,
        deviceName: String,
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
                session: Self(io: handshake.io, crypto: sessionCrypto, event: event, disconnected: disconnected),
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
        event: @escaping @Sendable (RemoteMessage) async -> Void,
        disconnected: @escaping @Sendable (Swift.Error) async -> Void = { _ in }
    ) async throws -> RemoteClientSession {
        guard credential.count == 32 else { throw RemoteKeychainClient.Error.invalidCredentialLength }
        let handshake = try await begin(endpoint: endpoint, expectedMacID: expectedMacID, deviceID: deviceID, deviceName: deviceName)
        do {
            let crypto = try makeCrypto(credential: credential, handshake: handshake)
            try await authenticate(io: handshake.io, crypto: crypto, credential: credential, transcript: handshake.transcript, deviceID: deviceID)
            return Self(io: handshake.io, crypto: crypto, event: event, disconnected: disconnected)
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
