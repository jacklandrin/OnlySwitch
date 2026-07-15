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

    @Test(.timeLimit(.minutes(1)))
    func clientPairingInteroperatesWithProductionWireProtocol() async throws {
        let macID = UUID()
        let deviceID = UUID()
        let code = "ABCDEFGH2345"
        let credential = Data(repeating: 11, count: 32)
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
            await io.cancel()
        }

        let result = try await RemoteClientSession.pair(
            endpoint: .hostPort(host: .ipv4(.loopback), port: port),
            expectedMacID: macID,
            code: code,
            deviceID: deviceID,
            deviceName: "Test iPhone",
            event: { _ in }
        )
        #expect(result.credential == credential)
        try await result.session.requestCatalog()
        try await server.value
        await result.session.close()
    }

    private func start(_ listener: NWListener) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready: continuation.resume()
                    case let .failed(error): continuation.resume(throwing: error)
                    case .cancelled: continuation.resume(throwing: CancellationError())
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
}

private actor ConnectionOperationRecorder {
    private(set) var events: [ConnectionOperation] = []
    func record(_ event: ConnectionOperation) { events.append(event) }
}
