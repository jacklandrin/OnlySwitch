import Foundation
import CryptoKit
import Network
import RemoteCore
import RemoteTransport
import Testing
@testable import OnlySwitchRemote

struct RemoteConnectionClientTests {
    private let firstMac = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let secondMac = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test func selectingMacClosesPreviousSessionBeforeConnectingNewOne() async {
        let recorder = ConnectionOperationRecorder()
        let coordinator = RemoteConnectionCoordinator(
            connect: { await recorder.record(.connect($0.id)) },
            disconnect: { await recorder.record(.disconnect($0)) }
        )

        await coordinator.select(.init(id: firstMac, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false))
        await coordinator.select(.init(id: secondMac, displayName: "Laptop", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false))

        #expect(await recorder.events == [.connect(firstMac), .disconnect(firstMac), .connect(secondMac)])
    }

    @Test func selectingNilDisconnectsAndDoesNotReconnect() async {
        let recorder = ConnectionOperationRecorder()
        let coordinator = RemoteConnectionCoordinator(
            connect: { await recorder.record(.connect($0.id)) },
            disconnect: { await recorder.record(.disconnect($0)) }
        )
        await coordinator.select(.init(id: firstMac, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false))

        await coordinator.select(nil)

        #expect(await recorder.events == [.connect(firstMac), .disconnect(firstMac)])
    }

    @Test func concurrentSelectionsRemainStrictlyFIFO() async {
        let recorder = ConnectionOperationRecorder()
        let gate = OperationGate()
        let secondID = secondMac
        let coordinator = RemoteConnectionCoordinator(
            connect: { mac in
                if mac.id == secondID, await gate.opened == false {
                    await recorder.record(.connectBeforePreviousFinished)
                }
                await recorder.record(.connect(mac.id))
                if mac.id == firstMac { await gate.wait() }
            },
            disconnect: { await recorder.record(.disconnect($0)) }
        )
        let first = PairedMac(id: firstMac, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
        let second = PairedMac(id: secondMac, displayName: "Laptop", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)

        let firstSelection = Task { await coordinator.select(first) }
        await gate.waitUntilEntered()
        let secondSelection = Task { await coordinator.select(second) }
        await Task.yield()

        #expect(await recorder.events == [.connect(firstMac)])
        await gate.open()
        await firstSelection.value
        await secondSelection.value
        #expect(await recorder.events == [.connect(firstMac), .disconnect(firstMac), .connect(secondMac)])
    }

    @Test(.timeLimit(.minutes(1)))
    func clientPairingInteroperatesWithProductionWireProtocol() async throws {
        let macID = UUID()
        let deviceID = UUID()
        let code = "ABCDEFGH2345"
        let credential = Data(repeating: 11, count: 32)
        let (clientEvents, clientEventContinuation) = AsyncStream.makeStream(
            of: RemoteMessage.self,
            bufferingPolicy: .bufferingNewest(8)
        )
        let listener = try NWListener(using: .tcp, on: .any)
        let (connections, connectionContinuation) = AsyncStream.makeStream(
            of: NWConnection.self,
            bufferingPolicy: .bufferingOldest(1)
        )
        listener.newConnectionHandler = { connectionContinuation.yield($0) }
        try await start(listener)
        defer {
            connectionContinuation.finish()
            listener.cancel()
        }
        let port = try #require(listener.port)
        let server = Task {
            var iterator = connections.makeAsyncIterator()
            let connection = try #require(await iterator.next())
            let io = RemoteConnectionIO(connection: connection)
            try await io.start()
            let first = try await io.receive()
            let client = try #require(first.plaintext)
            guard case let .clientHello(hello) = client else { throw TestProtocolError.unexpectedMessage }
            let key = P256.KeyAgreement.PrivateKey()
            let serverHello = ServerHello(
                version: .current,
                macID: macID,
                macName: "Studio",
                ephemeralPublicKey: key.publicKey.rawRepresentation,
                challenge: Data(repeating: 3, count: 32)
            )
            try await io.send(.plaintext(.serverHello(serverHello)))
            #expect(try await io.receive().plaintext == .pairingRequest)
            let proofPacket = try await io.receive()
            guard case let .pairingProof(proof)? = proofPacket.plaintext else { throw TestProtocolError.unexpectedMessage }
            let transcript = try RemoteHandshakeCrypto.transcript(client: hello, server: serverHello)
            let expectedProof = try RemoteSessionCrypto.makePairingProof(
                privateKey: key,
                peerPublicKey: hello.ephemeralPublicKey,
                pairingCode: code,
                transcript: transcript
            )
            #expect(proof.proof == expectedProof)
            let pairingCrypto = try makeServerCrypto(key: key, hello: hello, credential: Data(code.utf8), transcript: transcript)
            try await io.send(.encrypted(try pairingCrypto.seal(.pairingResult(.success(.init(macID: macID, credential: credential))))))
            let sessionCrypto = try makeServerCrypto(key: key, hello: hello, credential: credential, transcript: transcript)
            let authentication = try await receiveEncrypted(io: io, crypto: sessionCrypto)
            guard case let .authenticationProof(authenticationProof) = authentication else { throw TestProtocolError.unexpectedMessage }
            #expect(RemoteHandshakeCrypto.verifyAuthenticationProof(authenticationProof.proof, credential: credential, transcript: transcript))
            try await io.send(.encrypted(try sessionCrypto.seal(.authenticationResult(.success(.init(sessionID: UUID(), catalogRevision: 1))))))
            #expect(try await receiveEncrypted(io: io, crypto: sessionCrypto) == .catalogRequest)
            #expect(try await receiveEncrypted(io: io, crypto: sessionCrypto) == .subscriptionUpdate([.darkMode]))
            let actionMessage = try await receiveEncrypted(io: io, crypto: sessionCrypto)
            guard case let .actionRequest(request) = actionMessage else { throw TestProtocolError.unexpectedMessage }
            try await io.send(.encrypted(try sessionCrypto.seal(.actionResult(.init(requestID: request.requestID, result: .success(nil))))))
            try await io.send(.encrypted(try sessionCrypto.seal(.credentialRevoked)))
            await io.cancel()
        }

        let result = try await RemoteClientSession.pair(
            endpoint: .hostPort(host: .ipv4(.loopback), port: port),
            expectedMacID: macID,
            code: code,
            deviceID: deviceID,
            deviceName: "Test iPhone",
            event: { clientEventContinuation.yield($0) }
        )
        #expect(result.credential == credential)
        result.session.startReceiving()
        try await result.session.requestCatalog()
        try await result.session.subscribe([.darkMode])
        let request = RemoteActionRequest(requestID: UUID(), controlID: .darkMode, action: .setState(true))
        #expect(try await result.session.send(request).requestID == request.requestID)
        try await server.value
        var eventIterator = clientEvents.makeAsyncIterator()
        var sawRevocation = false
        while let message = await eventIterator.next() {
            if message == .credentialRevoked { sawRevocation = true; break }
        }
        #expect(sawRevocation)
        clientEventContinuation.finish()
        await result.session.close()
    }

    @Test(.timeLimit(.minutes(1)))
    func existingCredentialAuthenticatesWithoutPairing() async throws {
        let macID = UUID()
        let deviceID = UUID()
        let credential = Data(repeating: 17, count: 32)
        let listener = try NWListener(using: .tcp, on: .any)
        let (connections, connectionContinuation) = AsyncStream.makeStream(
            of: NWConnection.self,
            bufferingPolicy: .bufferingOldest(1)
        )
        listener.newConnectionHandler = { connectionContinuation.yield($0) }
        try await start(listener)
        defer {
            connectionContinuation.finish()
            listener.cancel()
        }
        let port = try #require(listener.port)
        let server = Task {
            var iterator = connections.makeAsyncIterator()
            let connection = try #require(await iterator.next())
            let io = RemoteConnectionIO(connection: connection)
            try await io.start()
            let first = try await io.receive()
            guard case let .clientHello(hello)? = first.plaintext else { throw TestProtocolError.unexpectedMessage }
            let key = P256.KeyAgreement.PrivateKey()
            let serverHello = ServerHello(
                version: .current,
                macID: macID,
                macName: "Studio",
                ephemeralPublicKey: key.publicKey.rawRepresentation,
                challenge: Data(repeating: 7, count: 32)
            )
            try await io.send(.plaintext(.serverHello(serverHello)))
            let transcript = try RemoteHandshakeCrypto.transcript(client: hello, server: serverHello)
            let crypto = try makeServerCrypto(
                key: key,
                hello: hello,
                credential: credential,
                transcript: transcript
            )
            let authentication = try await receiveEncrypted(io: io, crypto: crypto)
            guard case let .authenticationProof(proof) = authentication else { throw TestProtocolError.unexpectedMessage }
            #expect(proof.deviceID == deviceID)
            #expect(RemoteHandshakeCrypto.verifyAuthenticationProof(
                proof.proof,
                credential: credential,
                transcript: transcript
            ))
            try await io.send(.encrypted(try crypto.seal(.authenticationResult(.success(.init(
                sessionID: UUID(),
                catalogRevision: 3
            ))))))
            await io.cancel()
        }

        let session = try await RemoteClientSession.authenticate(
            endpoint: .hostPort(host: .ipv4(.loopback), port: port),
            expectedMacID: macID,
            credential: credential,
            deviceID: deviceID,
            deviceName: "Test iPad",
            event: { _ in }
        )

        try await server.value
        await session.close()
    }

    @Test(.timeLimit(.minutes(1)), arguments: [OfflineRevocationProofMode.valid, .replayedTranscript, .invalid])
    func offlineRevocationRequiresFreshValidProof(mode: OfflineRevocationProofMode) async throws {
        let macID = UUID()
        let deviceID = UUID()
        let credential = Data(repeating: 23, count: 32)
        let listener = try NWListener(using: .tcp, on: .any)
        let (connections, continuation) = AsyncStream.makeStream(
            of: NWConnection.self,
            bufferingPolicy: .bufferingOldest(1)
        )
        listener.newConnectionHandler = { continuation.yield($0) }
        try await start(listener)
        defer {
            continuation.finish()
            listener.cancel()
        }
        let port = try #require(listener.port)
        let server = Task {
            var iterator = connections.makeAsyncIterator()
            let connection = try #require(await iterator.next())
            let io = RemoteConnectionIO(connection: connection)
            try await io.start()
            guard case let .clientHello(hello)? = (try await io.receive()).plaintext else {
                throw TestProtocolError.unexpectedMessage
            }
            let key = P256.KeyAgreement.PrivateKey()
            let serverHello = ServerHello(
                version: .current,
                macID: macID,
                macName: "Studio",
                ephemeralPublicKey: key.publicKey.rawRepresentation,
                challenge: Data(repeating: 5, count: 32)
            )
            try await io.send(.plaintext(.serverHello(serverHello)))
            _ = try await io.receive()
            let transcript: Data
            switch mode {
            case .valid, .invalid:
                transcript = try RemoteHandshakeCrypto.transcript(client: hello, server: serverHello)
            case .replayedTranscript:
                transcript = try RemoteHandshakeCrypto.transcript(
                    client: hello,
                    server: .init(
                        version: .current,
                        macID: macID,
                        macName: "Studio",
                        ephemeralPublicKey: key.publicKey.rawRepresentation,
                        challenge: Data(repeating: 6, count: 32)
                    )
                )
            }
            let verifier = RemoteHandshakeCrypto.revocationVerifier(credential: credential)
            let proof = mode == .invalid
                ? Data(repeating: 0, count: 32)
                : RemoteHandshakeCrypto.revocationProof(verifier: verifier, transcript: transcript)
            try await io.send(.plaintext(.credentialRevocationProof(.init(
                deviceID: deviceID,
                proof: proof
            ))))
            await io.cancel()
        }

        do {
            _ = try await RemoteClientSession.authenticate(
                endpoint: .hostPort(host: .ipv4(.loopback), port: port),
                expectedMacID: macID,
                credential: credential,
                deviceID: deviceID,
                deviceName: "Test iPhone",
                event: { _ in }
            )
            Issue.record("Expected authentication to reject the revoked credential")
        } catch is RemoteClientSession.AuthenticatedCredentialRevocation {
            #expect(mode == .valid)
        } catch let error as RemoteProtocolError {
            #expect(mode != .valid)
            #expect(error.code == .authenticationFailed)
        }
        try await server.value
    }

    @Test(.timeLimit(.minutes(1)))
    func metadataFailureAfterRemoteAuthenticationRetainsNewCredential() async throws {
        let macID = UUID()
        let credential = Data(repeating: 31, count: 32)
        let server = try await PairingLoopbackServer.start(
            macID: macID,
            code: "ABCDEFGH2345",
            credential: credential
        )
        defer { server.cancel() }
        var persistence = RemotePersistenceClient.inMemory()
        persistence.upsertPairedMac = { _ in throw ConnectionStorageError.metadata }
        let keychain = RemoteKeychainClient.inMemory()
        let runtime = RemoteConnectionRuntime(persistence: persistence, keychain: keychain, deviceID: UUID())
        let discovered = DiscoveredMac(
            id: macID,
            displayName: "Studio",
            endpoint: server.endpoint,
            protocolVersion: .current
        )

        await #expect(throws: ConnectionStorageError.metadata) {
            try await runtime.pair(discovered, code: "ABCDEFGH2345", deviceName: "Test iPhone")
        }

        #expect(try await keychain.loadCredential(macID) == credential)
        await server.waitUntilFinished()
    }

    @Test(.timeLimit(.minutes(1)))
    func backgroundCancellationAfterRemoteAuthenticationRetainsNewCredential() async throws {
        let macID = UUID()
        let credential = Data(repeating: 32, count: 32)
        let server = try await PairingLoopbackServer.start(
            macID: macID,
            code: "ABCDEFGH2345",
            credential: credential
        )
        defer { server.cancel() }
        let gate = OperationGate()
        let credentialStore = GatedCredentialStore(gate: gate)
        let runtime = RemoteConnectionRuntime(
            persistence: .inMemory(),
            keychain: credentialStore.client,
            deviceID: UUID()
        )
        let discovered = DiscoveredMac(
            id: macID,
            displayName: "Studio",
            endpoint: server.endpoint,
            protocolVersion: .current
        )
        let pairing = Task {
            try await runtime.pair(discovered, code: "ABCDEFGH2345", deviceName: "Test iPad")
        }
        await gate.waitUntilEntered()

        await runtime.setForegrounded(false)
        await gate.open()

        await #expect(throws: CancellationError.self) { try await pairing.value }
        #expect(await credentialStore.load(macID) == credential)
        await server.waitUntilFinished()
    }

    @Test(.timeLimit(.minutes(1)))
    func catalogFailureAfterRemoteAuthenticationRetainsCredentialAndPairingMetadata() async throws {
        let macID = UUID()
        let credential = Data(repeating: 33, count: 32)
        let server = try await PairingLoopbackServer.start(
            macID: macID,
            code: "ABCDEFGH2345",
            credential: credential
        )
        defer { server.cancel() }
        let persistence = RemotePersistenceClient.inMemory()
        let keychain = RemoteKeychainClient.inMemory()
        let runtime = RemoteConnectionRuntime(
            persistence: persistence,
            keychain: keychain,
            deviceID: UUID(),
            catalogRequest: { _ in throw ConnectionStorageError.catalog }
        )
        let discovered = DiscoveredMac(
            id: macID,
            displayName: "Studio",
            endpoint: server.endpoint,
            protocolVersion: .current
        )

        let paired = try await runtime.pair(
            discovered,
            code: "ABCDEFGH2345",
            deviceName: "Test iPhone"
        )

        #expect(paired.id == macID)
        #expect(try await keychain.loadCredential(macID) == credential)
        #expect(try await persistence.loadPairedMacs().first?.requiresPairing == false)
        await server.waitUntilFinished()
    }

    @Test(.timeLimit(.minutes(1)))
    func rePairDuringLiveRevocationCloseCannotDeleteReplacementCredential() async throws {
        let macID = UUID()
        let oldCredential = Data(repeating: 41, count: 32)
        let newCredential = Data(repeating: 42, count: 32)
        let oldServer = try await PairingLoopbackServer.start(
            macID: macID,
            code: "ABCDEFGH2345",
            credential: oldCredential,
            sendRevocationAfterCatalog: true
        )
        defer { oldServer.cancel() }
        let closeGate = OperationGate()
        let credentialStore = ObservedCredentialStore()
        let persistence = RemotePersistenceClient.inMemory()
        let runtime = RemoteConnectionRuntime(
            persistence: persistence,
            keychain: credentialStore.client,
            deviceID: UUID(),
            closeSession: { session in
                await closeGate.wait()
                await session.close()
            }
        )
        _ = try await runtime.pair(
            .init(id: macID, displayName: "Studio", endpoint: oldServer.endpoint, protocolVersion: .current),
            code: "ABCDEFGH2345",
            deviceName: "Test iPhone"
        )
        await closeGate.waitUntilEntered()

        let newServer = try await PairingLoopbackServer.start(
            macID: macID,
            code: "ABCDEFGH2345",
            credential: newCredential
        )
        defer { newServer.cancel() }
        _ = try await runtime.pair(
            .init(id: macID, displayName: "Studio", endpoint: newServer.endpoint, protocolVersion: .current),
            code: "ABCDEFGH2345",
            deviceName: "Test iPhone"
        )
        await closeGate.open()
        await credentialStore.waitForConditionalDelete()

        #expect(await credentialStore.load(macID) == newCredential)
        #expect(try await persistence.loadPairedMacs().first?.requiresPairing == false)
        await oldServer.waitUntilFinished()
        await newServer.waitUntilFinished()
    }

    @Test func duplicateClaimedMacIDsHaveDeterministicCandidateOrder() {
        let id = UUID()
        let first = DiscoveredMac(
            id: id,
            displayName: "Studio",
            endpoint: .hostPort(host: "192.168.1.20", port: 19420),
            protocolVersion: .current
        )
        let second = DiscoveredMac(
            id: id,
            displayName: "Spoof",
            endpoint: .hostPort(host: "192.168.1.10", port: 19420),
            protocolVersion: .current
        )

        let forward = RemoteConnectionRuntime.orderedCandidates([first, second])
        let reverse = RemoteConnectionRuntime.orderedCandidates([second, first])

        #expect(forward == reverse)
        #expect(forward.count == 2)
    }

    @Test func candidateCapsEvictionAndPreferredEndpointAreDeterministic() {
        let id = UUID()
        let candidates = (0..<12).map { index in
            DiscoveredMac(
                id: id,
                displayName: "Candidate \(index)",
                endpoint: .hostPort(host: NWEndpoint.Host("192.168.1.\(index + 1)"), port: 19420),
                protocolVersion: .current
            )
        }
        let preferred = String(describing: candidates[11].endpoint)

        let forward = RemoteConnectionRuntime.boundedCandidates(
            candidates,
            preferredEndpoints: [id: preferred]
        )
        let reverse = RemoteConnectionRuntime.boundedCandidates(
            candidates.reversed(),
            preferredEndpoints: [id: preferred]
        )

        #expect(forward[id]?.count == RemoteConnectionRuntime.maximumCandidatesPerMac)
        let forwardKeys = Set(forward[id]?.keys.map { $0 } ?? [])
        let reverseKeys = Set(reverse[id]?.keys.map { $0 } ?? [])
        #expect(forwardKeys == reverseKeys)
        #expect(forward[id]?[preferred] != nil)
        #expect(RemoteConnectionRuntime.orderedCandidates(
            forward[id]?.values.map { $0 } ?? [],
            preferredEndpointDescription: preferred
        ).first?.endpoint == candidates[11].endpoint)
    }

    @Test func candidateSetChangeDetectsRealEndpointWhileSpoofPersists() {
        let id = UUID()
        let spoof = DiscoveredMac(
            id: id,
            displayName: "Spoof",
            endpoint: .hostPort(host: "192.168.1.10", port: 19420),
            protocolVersion: .current
        )
        let real = DiscoveredMac(
            id: id,
            displayName: "Studio",
            endpoint: .hostPort(host: "192.168.1.20", port: 19420),
            protocolVersion: .current
        )
        let spoofKey = String(describing: spoof.endpoint)
        let realKey = String(describing: real.endpoint)

        #expect(RemoteConnectionRuntime.candidateSetChanged(
            previous: [spoofKey: spoof],
            updated: [spoofKey: spoof, realKey: real]
        ))
    }

    @Test func globalCandidateCapIsEnforcedAcrossClaimedMacIDs() {
        let candidates = (0..<80).map { index in
            DiscoveredMac(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index / 8))!,
                displayName: "Candidate \(index)",
                endpoint: .hostPort(
                    host: NWEndpoint.Host("10.0.\(index / 250).\(index % 250 + 1)"),
                    port: 19420
                ),
                protocolVersion: .current
            )
        }

        let bounded = RemoteConnectionRuntime.boundedCandidates(candidates)

        #expect(bounded.values.reduce(0) { $0 + $1.count } == RemoteConnectionRuntime.maximumCandidatesGlobally)
    }

    @Test func staleSameMacSessionCallbacksAreRejected() {
        let macID = UUID()
        let oldToken = UUID()
        let currentToken = UUID()

        #expect(!RemoteConnectionRuntime.isCurrentSession(
            selectedMacID: macID,
            currentToken: currentToken,
            eventMacID: macID,
            eventToken: oldToken
        ))
        #expect(RemoteConnectionRuntime.isCurrentSession(
            selectedMacID: macID,
            currentToken: currentToken,
            eventMacID: macID,
            eventToken: currentToken
        ))
        #expect(!RemoteConnectionRuntime.shouldClearSession(
            currentToken: currentToken,
            failedToken: oldToken
        ))
        #expect(RemoteConnectionRuntime.shouldClearSession(
            currentToken: currentToken,
            failedToken: currentToken
        ))
    }

    @Test func discoveryStreamOwnsBrowserLifecycle() async {
        let recorder = StreamLifecycleRecorder()
        let hub = RemoteStreamHub<DiscoveryEvent>()
        let stream = hub.stream(
            bufferingPolicy: .bufferingNewest(1),
            onFirstSubscriber: { recorder.recordStart() },
            onNoSubscribers: { recorder.recordStop() }
        )

        #expect(hub.subscriberCount == 1)
        #expect(recorder.values == (starts: 1, stops: 0))

        let consumer = Task {
            for await _ in stream {}
        }
        consumer.cancel()
        await consumer.value

        #expect(hub.subscriberCount == 0)
        #expect(recorder.values == (starts: 1, stops: 1))
    }

    @Test func browserRestartBackoffIsBounded() {
        #expect(RemoteConnectionRuntime.browserRetryDelay(failureCount: 0) == .milliseconds(500))
        #expect(RemoteConnectionRuntime.browserRetryDelay(failureCount: 2) == .seconds(2))
        #expect(RemoteConnectionRuntime.browserRetryDelay(failureCount: 99) == .seconds(8))
    }

    @Test func foregroundWinsWhileBackgroundCleanupIsSuspended() async {
        let gate = OperationGate()
        let runtime = RemoteConnectionRuntime(
            persistence: .inMemory(),
            keychain: .inMemory(),
            deviceID: UUID(),
            backgroundCleanup: { await gate.wait() }
        )
        let discovery = runtime.makeDiscoveryStream()
        let background = Task { await runtime.setForegrounded(false) }
        await gate.waitUntilEntered()

        await runtime.setForegrounded(true)
        await gate.open()
        await background.value

        let snapshot = await runtime.lifecycleSnapshot
        #expect(snapshot.foregrounded)
        #expect(snapshot.ownsBrowser)
        _ = discovery
    }

    @Test func backgroundAndNewerPairingInvalidatePendingCommit() {
        let old = UUID()
        let newer = UUID()

        #expect(!RemoteConnectionRuntime.mayCommitPairing(
            activeToken: old,
            candidateToken: old,
            currentGeneration: 4,
            expectedGeneration: 4,
            foregrounded: false
        ))
        #expect(!RemoteConnectionRuntime.mayCommitPairing(
            activeToken: newer,
            candidateToken: old,
            currentGeneration: 5,
            expectedGeneration: 4,
            foregrounded: true
        ))
        #expect(RemoteConnectionRuntime.mayCommitPairing(
            activeToken: old,
            candidateToken: old,
            currentGeneration: 4,
            expectedGeneration: 4,
            foregrounded: true
        ))
    }

    @Test func genericAuthenticationFailureIsNotAuthoritativeRevocation() {
        let generic = RemoteMessage.sessionError(.init(code: .authenticationFailed, message: "Authentication failed"))

        #expect(!RemoteConnectionRuntime.isAuthoritativeRevocation(generic))
        #expect(RemoteConnectionRuntime.isAuthoritativeRevocation(.credentialRevoked))
    }

    private func start(_ listener: NWListener) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let startContinuation = ListenerStartContinuation(continuation)
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready: startContinuation.resume()
                    case let .failed(error): startContinuation.resume(throwing: error)
                    case .cancelled: startContinuation.resume(throwing: CancellationError())
                    default: break
                    }
                }
                listener.start(queue: .global(qos: .userInitiated))
            }
        } onCancel: {
            listener.cancel()
        }
    }

    private func makeServerCrypto(
        key: P256.KeyAgreement.PrivateKey,
        hello: ClientHello,
        credential: Data,
        transcript: Data
    ) throws -> RemoteSessionCrypto {
        let keys = try RemoteSessionCrypto.deriveSessionKeys(
            role: .server,
            privateKey: key,
            peerPublicKey: hello.ephemeralPublicKey,
            credential: credential,
            transcript: transcript
        )
        return RemoteSessionCrypto(sendKey: keys.send, receiveKey: keys.receive, noncePrefix: 123)
    }

    private func receiveEncrypted(io: RemoteConnectionIO, crypto: RemoteSessionCrypto) async throws -> RemoteMessage {
        let packet = try await io.receive()
        guard let encrypted = packet.encrypted else { throw TestProtocolError.unexpectedMessage }
        return try crypto.open(encrypted)
    }
}

private enum TestProtocolError: Swift.Error { case unexpectedMessage }
private enum ConnectionStorageError: Swift.Error, Equatable { case metadata, catalog }

enum OfflineRevocationProofMode: Sendable {
    case valid
    case replayedTranscript
    case invalid
}

private enum ConnectionOperation: Equatable, Sendable {
    case connect(UUID)
    case disconnect(UUID)
    case connectBeforePreviousFinished
}

private actor ConnectionOperationRecorder {
    private(set) var events: [ConnectionOperation] = []
    func record(_ event: ConnectionOperation) { events.append(event) }
}

private actor OperationGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var entered = false
    var opened: Bool { isOpen }

    func wait() async {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        guard isOpen == false else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func waitUntilEntered() async {
        guard entered == false else { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}

private final class StreamLifecycleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0

    var values: (starts: Int, stops: Int) {
        lock.withLock { (starts, stops) }
    }

    func recordStart() {
        lock.withLock { starts += 1 }
    }

    func recordStop() {
        lock.withLock { stops += 1 }
    }
}

private final class ListenerStartContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Swift.Error>?

    init(_ continuation: CheckedContinuation<Void, Swift.Error>) {
        self.continuation = continuation
    }

    func resume() {
        take()?.resume()
    }

    func resume(throwing error: Swift.Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Void, Swift.Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}

private final class PairingLoopbackServer: @unchecked Sendable {
    let endpoint: NWEndpoint
    private let listener: NWListener
    private let task: Task<Void, Never>

    private init(endpoint: NWEndpoint, listener: NWListener, task: Task<Void, Never>) {
        self.endpoint = endpoint
        self.listener = listener
        self.task = task
    }

    static func start(
        macID: UUID,
        code: String,
        credential: Data,
        sendRevocationAfterCatalog: Bool = false
    ) async throws -> PairingLoopbackServer {
        let listener = try NWListener(using: .tcp, on: .any)
        let (connections, continuation) = AsyncStream.makeStream(
            of: NWConnection.self,
            bufferingPolicy: .bufferingOldest(1)
        )
        listener.newConnectionHandler = { continuation.yield($0) }
        try await startListener(listener)
        let port = try #require(listener.port)
        let task = Task {
            defer { continuation.finish() }
            do {
                var iterator = connections.makeAsyncIterator()
                guard let connection = await iterator.next() else { return }
                let io = RemoteConnectionIO(connection: connection)
                try await io.start()
                guard case let .clientHello(hello)? = (try await io.receive()).plaintext else { return }
                let key = P256.KeyAgreement.PrivateKey()
                let serverHello = ServerHello(
                    version: .current,
                    macID: macID,
                    macName: "Studio",
                    ephemeralPublicKey: key.publicKey.rawRepresentation,
                    challenge: Data(repeating: 3, count: 32)
                )
                try await io.send(.plaintext(.serverHello(serverHello)))
                guard (try await io.receive()).plaintext == .pairingRequest,
                      case .pairingProof? = (try await io.receive()).plaintext else { return }
                let transcript = try RemoteHandshakeCrypto.transcript(client: hello, server: serverHello)
                let pairingCrypto = try makeCrypto(
                    key: key,
                    hello: hello,
                    credential: Data(code.utf8),
                    transcript: transcript
                )
                try await io.send(.encrypted(try pairingCrypto.seal(.pairingResult(.success(.init(
                    macID: macID,
                    credential: credential
                ))))))
                let sessionCrypto = try makeCrypto(
                    key: key,
                    hello: hello,
                    credential: credential,
                    transcript: transcript
                )
                guard case .authenticationProof = try await receive(io: io, crypto: sessionCrypto) else { return }
                try await io.send(.encrypted(try sessionCrypto.seal(.authenticationResult(.success(.init(
                    sessionID: UUID(),
                    catalogRevision: 1
                ))))))
                if let request = try? await io.receive(),
                   sendRevocationAfterCatalog,
                   request.encrypted != nil {
                    try await io.send(.encrypted(try sessionCrypto.seal(.credentialRevoked)))
                    _ = try? await io.receive()
                }
                await io.cancel()
            } catch {
                // Connection teardown is expected in cancellation-path tests.
            }
        }
        return PairingLoopbackServer(
            endpoint: .hostPort(host: .ipv4(.loopback), port: port),
            listener: listener,
            task: task
        )
    }

    func waitUntilFinished() async { await task.value }

    func cancel() {
        task.cancel()
        listener.cancel()
    }

    private static func startListener(_ listener: NWListener) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ListenerStartContinuation(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: gate.resume()
                case let .failed(error): gate.resume(throwing: error)
                case .cancelled: gate.resume(throwing: CancellationError())
                default: break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    private static func makeCrypto(
        key: P256.KeyAgreement.PrivateKey,
        hello: ClientHello,
        credential: Data,
        transcript: Data
    ) throws -> RemoteSessionCrypto {
        let keys = try RemoteSessionCrypto.deriveSessionKeys(
            role: .server,
            privateKey: key,
            peerPublicKey: hello.ephemeralPublicKey,
            credential: credential,
            transcript: transcript
        )
        return RemoteSessionCrypto(sendKey: keys.send, receiveKey: keys.receive, noncePrefix: 991)
    }

    private static func receive(io: RemoteConnectionIO, crypto: RemoteSessionCrypto) async throws -> RemoteMessage {
        let packet = try await io.receive()
        guard let encrypted = packet.encrypted else { throw TestProtocolError.unexpectedMessage }
        return try crypto.open(encrypted)
    }
}

private actor GatedCredentialStore {
    private let gate: OperationGate
    private var credentials: [UUID: Data] = [:]

    init(gate: OperationGate) { self.gate = gate }

    nonisolated var client: RemoteKeychainClient {
        RemoteKeychainClient(
            saveCredential: { [weak self] id, credential in
                guard let self else { throw CancellationError() }
                await self.save(id, credential: credential)
            },
            loadCredential: { [weak self] id in await self?.load(id) },
            deleteCredential: { [weak self] id in await self?.delete(id) },
            deleteCredentialIfMatches: { [weak self] id, expected in
                await self?.delete(id, matching: expected) ?? false
            }
        )
    }

    func load(_ id: UUID) -> Data? { credentials[id] }

    private func save(_ id: UUID, credential: Data) async {
        await gate.wait()
        credentials[id] = credential
    }

    private func delete(_ id: UUID) { credentials[id] = nil }

    private func delete(_ id: UUID, matching expected: Data) -> Bool {
        guard credentials[id] == expected else { return false }
        credentials[id] = nil
        return true
    }
}

private actor ObservedCredentialStore {
    private var credentials: [UUID: Data] = [:]
    private var deleteWaiters: [CheckedContinuation<Void, Never>] = []
    private var deleteAttempted = false

    nonisolated var client: RemoteKeychainClient {
        RemoteKeychainClient(
            saveCredential: { [weak self] id, value in await self?.save(id, value: value) },
            loadCredential: { [weak self] id in await self?.load(id) },
            deleteCredential: { [weak self] id in await self?.delete(id) },
            deleteCredentialIfMatches: { [weak self] id, expected in
                await self?.delete(id, matching: expected) ?? false
            }
        )
    }

    func load(_ id: UUID) -> Data? { credentials[id] }

    func waitForConditionalDelete() async {
        guard deleteAttempted == false else { return }
        await withCheckedContinuation { deleteWaiters.append($0) }
    }

    private func save(_ id: UUID, value: Data) { credentials[id] = value }
    private func delete(_ id: UUID) { credentials[id] = nil }

    private func delete(_ id: UUID, matching expected: Data) -> Bool {
        deleteAttempted = true
        let waiters = deleteWaiters
        deleteWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        guard credentials[id] == expected else { return false }
        credentials[id] = nil
        return true
    }
}
