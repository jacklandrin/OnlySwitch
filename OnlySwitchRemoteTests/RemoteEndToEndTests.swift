import ComposableArchitecture
import CryptoKit
import Foundation
import Network
import RemoteCore
import RemoteTransport
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteEndToEndTests {
    @Test(.timeLimit(.minutes(1)))
    func productionDeadlineIgnoresLateResultAndAllowsSameRequestIDRetry() async throws {
        let macID = UUID()
        let code = "ABCDEFGH2345"
        let descriptor = RemoteControlDescriptor(
            id: .darkMode,
            title: "Dark Mode",
            behavior: .switch,
            icon: .systemSymbol("moon"),
            isAvailable: true,
            unavailableReason: nil,
            isDestructive: false,
            supportsStatus: true,
            supportsSecondaryInformation: false
        )
        let server = try await DashboardLoopbackServer.start(
            macID: macID,
            pairingCode: code,
            credential: Data(repeating: 9, count: 32),
            descriptor: descriptor,
            initialStatus: status(isOn: false, revision: 1),
            updatedStatus: status(isOn: true, revision: 2),
            actionBehavior: .delayFirstResultUntilReleased
        )
        defer { server.cancel() }
        let runtime = RemoteConnectionRuntime(
            persistence: .inMemory(),
            keychain: .inMemory(),
            deviceID: UUID(),
            actionTimeout: .milliseconds(250)
        )
        var iterator = runtime.makeConnectionEventStream().makeAsyncIterator()
        _ = try await runtime.pair(
            .init(id: macID, displayName: "Studio", endpoint: server.endpoint, protocolVersion: .current),
            code: code,
            deviceName: "Test iPhone"
        )
        var sessionID: UUID?
        while sessionID == nil, let event = await iterator.next() {
            if case let .sessionStarted(_, id) = event { sessionID = id }
        }
        let liveSessionID = try #require(sessionID)
        try await runtime.subscribe([.darkMode])

        let request = RemoteActionRequest(requestID: UUID(), controlID: .darkMode, action: .setState(true))
        do {
            _ = try await runtime.send(.init(macID: macID, sessionID: UUID(), request: request))
            Issue.record("Expected stale session rejection")
        } catch let error as RemoteProtocolError {
            #expect(error.code == .authenticationFailed)
        }
        do {
            _ = try await runtime.send(.init(macID: macID, sessionID: liveSessionID, request: request))
            Issue.record("Expected action timeout")
        } catch let error as RemoteProtocolError {
            #expect(error.code == .requestTimedOut)
        }
        #expect(await server.operationCount == 1)

        await server.releaseFirstActionResult()
        var receivedLateResultMarker = false
        while let event = await iterator.next() {
            if case let .status(_, value) = event, value.revision == 2 {
                receivedLateResultMarker = true
                break
            }
        }
        #expect(receivedLateResultMarker)

        let retryResult = try await runtime.send(.init(
            macID: macID,
            sessionID: liveSessionID,
            request: request
        ))
        #expect(retryResult.requestID == request.requestID)
        #expect(try retryResult.result.get()?.revision == 2)
        #expect(await server.actionRequestIDs == [request.requestID, request.requestID])
        await runtime.setForegrounded(false)
    }

    @Test(.timeLimit(.minutes(1)))
    func secureLoopbackDrivesDashboardThroughPairCatalogSubscriptionAndAction() async throws {
        let macID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let pairingCode = "ABCDEFGH2345"
        let credential = Data((0..<32).map(UInt8.init))
        let descriptor = RemoteControlDescriptor(
            id: .darkMode,
            title: "Dark Mode",
            behavior: .switch,
            icon: .systemSymbol("moon"),
            isAvailable: true,
            unavailableReason: nil,
            isDestructive: false,
            supportsStatus: true,
            supportsSecondaryInformation: true
        )
        let initialStatus = status(isOn: false, revision: 1)
        let updatedStatus = status(isOn: true, revision: 2)
        let server = try await DashboardLoopbackServer.start(
            macID: macID,
            pairingCode: pairingCode,
            credential: credential,
            descriptor: descriptor,
            initialStatus: initialStatus,
            updatedStatus: updatedStatus
        )
        defer { server.cancel() }

        let runtimePersistence = RemotePersistenceClient.inMemory()
        let runtimeKeychain = RemoteKeychainClient.inMemory()
        let runtime = RemoteConnectionRuntime(
            persistence: runtimePersistence,
            keychain: runtimeKeychain,
            deviceID: UUID()
        )
        var connection = RemoteConnectionClient.testValue
        connection.events = { runtime.makeConnectionEventStream() }
        connection.snapshot = { await runtime.snapshot() }
        connection.subscribe = { try await runtime.subscribe($0) }
        connection.send = { try await runtime.send($0) }
        connection.setForegrounded = { await runtime.setForegrounded($0) }

        let mac = PairedMac(
            id: macID,
            displayName: "Studio",
            lastEndpointDescription: nil,
            lastConnectedAt: .now,
            requiresPairing: false
        )
        var rootState = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        rootState.pairedMacs = [mac]
        rootState.selectedMacID = macID
        rootState.dashboard = .init(
            pairedMacs: [mac],
            selectedMacID: macID,
            orderedSelectedIDs: [.darkMode],
            connectionState: .idle,
            isActive: true
        )
        let store = Store(initialState: rootState) { RemoteAppFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.remoteConnection = connection
            $0.remotePersistence.loadPairedMacs = { throw RemoteDependencyError.unimplemented }
            $0.remotePersistence.loadSelectedMacID = { nil }
        }
        store.send(.task)

        _ = try await runtime.pair(
            .init(id: macID, displayName: "Studio", endpoint: server.endpoint, protocolVersion: .current),
            code: pairingCode,
            deviceName: "Test iPhone"
        )
        try await waitUntil {
            store.dashboard.descriptors[id: .darkMode] == descriptor
                && store.dashboard.statuses[.darkMode]?.value == initialStatus
                && store.dashboard.activeSessionID != nil
        }
        #expect(try await runtimeKeychain.loadCredential(macID) == credential)
        #expect(try await runtimePersistence.loadCatalog(macID)?.controls == [descriptor])
        #expect(try await runtimePersistence.loadStatuses(macID) == [initialStatus])

        store.send(.dashboard(.tileTapped(.darkMode)))
        try await waitUntil {
            store.dashboard.statuses[.darkMode]?.value == updatedStatus
        }
        #expect(store.dashboard.statuses[.darkMode]?.isStale == false)
        #expect(await server.operationCount == 1)

        server.cancel()
        try await waitUntil { store.dashboard.canSendActions == false }
        await runtime.setForegrounded(false)

        await server.waitUntilFinished()
        let captured = await server.capturedFrames
        #expect(captured.isEmpty == false)
        #expect(captured.allSatisfy { $0.range(of: Data(pairingCode.utf8)) == nil })
        #expect(captured.allSatisfy { $0.range(of: credential) == nil })
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while condition() == false {
            guard clock.now < deadline else {
                throw RemoteProtocolError(code: .requestTimedOut, message: "Integration state did not converge")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func status(isOn: Bool, revision: UInt64) -> RemoteControlStatus {
        .init(
            id: .darkMode,
            isAvailable: true,
            unavailableReason: nil,
            isOn: isOn,
            secondaryInformation: isOn ? "On" : "Off",
            isProcessing: false,
            revision: revision,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(revision))
        )
    }
}

private actor DashboardFrameRecorder {
    private var values: [Data] = []

    func record(_ packet: RemoteWirePacket, sequence: UInt64) throws {
        values.append(try RemoteFrameCodec().encode(packet, sequence: sequence))
    }

    var frames: [Data] { values }
}

private final class DashboardLoopbackServer: @unchecked Sendable {
    enum ActionBehavior: Equatable, Sendable {
        case respondImmediately
        case delayFirstResultUntilReleased
    }

    let endpoint: NWEndpoint
    private let listener: NWListener
    private let task: Task<Void, Never>
    private let recorder: DashboardFrameRecorder
    private let operations: DashboardOperationRecorder

    private init(
        endpoint: NWEndpoint,
        listener: NWListener,
        task: Task<Void, Never>,
        recorder: DashboardFrameRecorder,
        operations: DashboardOperationRecorder
    ) {
        self.endpoint = endpoint
        self.listener = listener
        self.task = task
        self.recorder = recorder
        self.operations = operations
    }

    static func start(
        macID: UUID,
        pairingCode: String,
        credential: Data,
        descriptor: RemoteControlDescriptor,
        initialStatus: RemoteControlStatus,
        updatedStatus: RemoteControlStatus,
        actionBehavior: ActionBehavior = .respondImmediately
    ) async throws -> DashboardLoopbackServer {
        let listener = try NWListener(using: .tcp, on: .any)
        let (connections, connectionContinuation) = AsyncStream.makeStream(
            of: NWConnection.self,
            bufferingPolicy: .bufferingOldest(1)
        )
        listener.newConnectionHandler = { connectionContinuation.yield($0) }
        try await startListener(listener)
        let port = try #require(listener.port)
        let recorder = DashboardFrameRecorder()
        let operations = DashboardOperationRecorder()
        let task = Task {
            defer { connectionContinuation.finish() }
            do {
                var iterator = connections.makeAsyncIterator()
                let connection = try #require(await iterator.next())
                let io = RemoteConnectionIO(connection: connection)
                try await io.start()

                let helloPacket = try await io.receive()
                try await recorder.record(helloPacket, sequence: 0)
                guard case let .clientHello(hello)? = helloPacket.plaintext else { throw DashboardWireError.unexpected }
                let key = P256.KeyAgreement.PrivateKey()
                let serverHello = ServerHello(
                    version: .current,
                    macID: macID,
                    macName: "Studio",
                    ephemeralPublicKey: key.publicKey.rawRepresentation,
                    challenge: Data(repeating: 7, count: 32)
                )
                try await send(.plaintext(.serverHello(serverHello)), io: io, recorder: recorder, sequence: 0)
                let pairingRequest = try await io.receive()
                try await recorder.record(pairingRequest, sequence: 1)
                guard pairingRequest.plaintext == .pairingRequest else { throw DashboardWireError.unexpected }
                let pairingProof = try await io.receive()
                try await recorder.record(pairingProof, sequence: 2)
                guard case .pairingProof? = pairingProof.plaintext else { throw DashboardWireError.unexpected }

                let transcript = try RemoteHandshakeCrypto.transcript(client: hello, server: serverHello)
                let pairingCrypto = try makeCrypto(
                    key: key,
                    hello: hello,
                    credential: Data(pairingCode.utf8),
                    transcript: transcript
                )
                let pairingResult = RemoteWirePacket.encrypted(try pairingCrypto.seal(.pairingResult(.success(.init(
                    macID: macID,
                    credential: credential
                )))))
                try await send(pairingResult, io: io, recorder: recorder, sequence: 1)

                let sessionCrypto = try makeCrypto(key: key, hello: hello, credential: credential, transcript: transcript)
                let authentication = try await io.receive()
                try await recorder.record(authentication, sequence: 3)
                guard case .authenticationProof = try decrypt(authentication, crypto: sessionCrypto) else {
                    throw DashboardWireError.unexpected
                }
                try await send(
                    .encrypted(try sessionCrypto.seal(.authenticationResult(.success(.init(
                        sessionID: UUID(),
                        catalogRevision: 1
                    ))))),
                    io: io,
                    recorder: recorder,
                    sequence: 2
                )

                let catalogRequest = try await io.receive()
                try await recorder.record(catalogRequest, sequence: 4)
                guard try decrypt(catalogRequest, crypto: sessionCrypto) == .catalogRequest else {
                    throw DashboardWireError.unexpected
                }
                try await send(
                    .encrypted(try sessionCrypto.seal(.catalogSnapshot(revision: 1, controls: [descriptor]))),
                    io: io,
                    recorder: recorder,
                    sequence: 3
                )

                let subscription = try await io.receive()
                try await recorder.record(subscription, sequence: 5)
                guard try decrypt(subscription, crypto: sessionCrypto) == .subscriptionUpdate([.darkMode]) else {
                    throw DashboardWireError.unexpected
                }
                try await send(
                    .encrypted(try sessionCrypto.seal(.statusSnapshot([initialStatus]))),
                    io: io,
                    recorder: recorder,
                    sequence: 4
                )

                let actionPacket = try await io.receive()
                try await recorder.record(actionPacket, sequence: 6)
                guard case let .actionRequest(request) = try decrypt(actionPacket, crypto: sessionCrypto) else {
                    throw DashboardWireError.unexpected
                }
                await operations.record(request.requestID)
                if actionBehavior == .delayFirstResultUntilReleased {
                    await operations.waitForFirstResultRelease()
                }
                try await send(
                    .encrypted(try sessionCrypto.seal(.actionResult(.init(
                        requestID: request.requestID,
                        result: .success(updatedStatus)
                    )))),
                    io: io,
                    recorder: recorder,
                    sequence: 5
                )
                try await send(
                    .encrypted(try sessionCrypto.seal(.statusChanged(updatedStatus))),
                    io: io,
                    recorder: recorder,
                    sequence: 6
                )
                if actionBehavior == .delayFirstResultUntilReleased {
                    let retryPacket = try await io.receive()
                    try await recorder.record(retryPacket, sequence: 7)
                    guard case let .actionRequest(retry) = try decrypt(retryPacket, crypto: sessionCrypto) else {
                        throw DashboardWireError.unexpected
                    }
                    await operations.record(retry.requestID)
                    try await send(
                        .encrypted(try sessionCrypto.seal(.actionResult(.init(
                            requestID: retry.requestID,
                            result: .success(updatedStatus)
                        )))),
                        io: io,
                        recorder: recorder,
                        sequence: 7
                    )
                }
                _ = try? await io.receive()
                await io.cancel()
            } catch {
                // The client closing after the verified action is expected.
            }
        }
        return DashboardLoopbackServer(
            endpoint: .hostPort(host: .ipv4(.loopback), port: port),
            listener: listener,
            task: task,
            recorder: recorder,
            operations: operations
        )
    }

    var capturedFrames: [Data] { get async { await recorder.frames } }
    var operationCount: Int { get async { await operations.count } }
    var actionRequestIDs: [UUID] { get async { await operations.requestIDs } }
    func releaseFirstActionResult() async { await operations.releaseFirstResult() }
    func waitUntilFinished() async { await task.value }
    func cancel() { task.cancel(); listener.cancel() }

    private static func startListener(_ listener: NWListener) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let gate = DashboardListenerGate(continuation)
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
        return RemoteSessionCrypto(sendKey: keys.send, receiveKey: keys.receive, noncePrefix: 771)
    }

    private static func send(
        _ packet: RemoteWirePacket,
        io: RemoteConnectionIO,
        recorder: DashboardFrameRecorder,
        sequence: UInt64
    ) async throws {
        try await recorder.record(packet, sequence: sequence)
        try await io.send(packet)
    }

    private static func decrypt(
        _ packet: RemoteWirePacket,
        crypto: RemoteSessionCrypto
    ) throws -> RemoteMessage {
        guard let frame = packet.encrypted else { throw DashboardWireError.unexpected }
        return try crypto.open(frame)
    }
}

private actor DashboardOperationRecorder {
    private(set) var count = 0
    private(set) var requestIDs: [UUID] = []
    private var firstResultReleased = false
    private var firstResultReleaseWaiter: CheckedContinuation<Void, Never>?

    func record(_ requestID: UUID) {
        count += 1
        requestIDs.append(requestID)
    }

    func waitForFirstResultRelease() async {
        guard firstResultReleased == false else { return }
        await withCheckedContinuation { firstResultReleaseWaiter = $0 }
    }

    func releaseFirstResult() {
        firstResultReleased = true
        firstResultReleaseWaiter?.resume()
        firstResultReleaseWaiter = nil
    }
}

private enum DashboardWireError: Swift.Error { case unexpected }

private final class DashboardListenerGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Swift.Error>?

    init(_ continuation: CheckedContinuation<Void, Swift.Error>) {
        self.continuation = continuation
    }

    func resume() { take()?.resume() }
    func resume(throwing error: Swift.Error) { take()?.resume(throwing: error) }

    private func take() -> CheckedContinuation<Void, Swift.Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}
