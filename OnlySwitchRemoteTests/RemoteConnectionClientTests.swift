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
