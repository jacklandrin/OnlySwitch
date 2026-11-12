import CryptoKit
import Foundation
import Network
import RemoteCore
import RemoteTransport

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
    nonisolated let protocolVersion: RemoteProtocolVersion
    private let io: RemoteConnectionIO
    private let crypto: RemoteSessionCrypto
    private let event: @Sendable (RemoteMessage) async -> Void
    private let disconnected: @Sendable (Swift.Error) async -> Void
    private let actionResponses = RemoteActionResponses()
    private let codexUsageResponses = RemoteCodexUsageResponses()
    private let claudeUsageResponses = RemoteClaudeUsageResponses()
    private let screenshotResponses = RemoteScreenshotResponses()
    private var receiveTask: Task<Void, Never>?
    private var closed = false

    private init(
        io: RemoteConnectionIO,
        crypto: RemoteSessionCrypto,
        credentialIdentity: Data,
        protocolVersion: RemoteProtocolVersion,
        token: UUID,
        event: @escaping @Sendable (RemoteMessage) async -> Void,
        disconnected: @escaping @Sendable (Swift.Error) async -> Void
    ) {
        self.token = token
        self.io = io
        self.crypto = crypto
        self.credentialIdentity = credentialIdentity
        self.protocolVersion = protocolVersion
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
                    protocolVersion: handshake.server.version,
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
                protocolVersion: handshake.server.version,
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
    func requestAphroditeLibraryIfSupported() async throws {
        guard protocolVersion.supportsAphroditeRemote else { return }
        try await sendMessage(.aphroditeLibraryRequest)
    }
    func sendSoundMixer(_ command: RemoteSoundMixerCommand) async throws {
        guard protocolVersion.supportsSoundMixerRemote else {
            throw RemoteProtocolError(code: .actionNotSupported, message: "Sound Mixer remote control is unavailable on this Mac")
        }
        if command.requiresSoundMixerTab, protocolVersion.supportsSoundMixerTabRemote == false {
            throw Self.soundMixerUpgradeRequired
        }
        if command.requiresEqualizerPresets, protocolVersion.supportsEqualizerPresetsRemote == false {
            throw Self.soundMixerUpgradeRequired
        }
        try await sendMessage(.soundMixerCommand(command))
    }
    func setSoundMixerStreaming(_ enabled: Bool) async throws {
        guard protocolVersion.supportsSoundMixerTabRemote else { throw Self.soundMixerUpgradeRequired }
        try await sendMessage(.soundMixerSubscriptionUpdate(enabled))
    }
    private static let soundMixerUpgradeRequired = RemoteProtocolError(
        code: .upgradeRequired,
        message: "Sound Mixer requires a newer OnlySwitch"
    )
    func setBrightnessStreaming(_ enabled: Bool) async throws {
        guard protocolVersion.supportsBrightnessRemote else { throw Self.brightnessUpgradeRequired }
        try await sendMessage(.brightnessSubscriptionUpdate(enabled))
    }
    func sendBrightness(_ command: RemoteBrightnessCommand) async throws {
        guard protocolVersion.supportsBrightnessRemote else { throw Self.brightnessUpgradeRequired }
        try await sendMessage(.brightnessCommand(command))
    }
    private static let brightnessUpgradeRequired = RemoteProtocolError(
        code: .upgradeRequired,
        message: "Brightness requires a newer OnlySwitch"
    )
    func setScreenshotsStreaming(_ enabled: Bool) async throws {
        guard protocolVersion.supportsScreenshotsRemote else { throw Self.screenshotsUpgradeRequired }
        guard enabled == false else {
            try await sendMessage(.screenshotsSubscriptionUpdate(true))
            return
        }
        // The Mac drops pending thumbnail/image work on unsubscribe without replying,
        // so fail every awaiter here whether or not the update could be sent.
        do {
            try await sendMessage(.screenshotsSubscriptionUpdate(false))
        } catch {
            await screenshotResponses.finishAll()
            throw error
        }
        await screenshotResponses.finishAll()
    }
    func fetchScreenshotThumbnails(_ request: RemoteScreenshotThumbnailsRequest) async throws -> RemoteScreenshotThumbnailsResult {
        let response = try await screenshotRequest(request.requestID, kind: .thumbnails, .screenshotThumbnailsRequest(request))
        guard case let .thumbnails(result) = response else { throw Self.unexpectedScreenshotReply }
        return result
    }
    func fetchScreenshotImage(_ request: RemoteScreenshotImageRequest) async throws -> RemoteScreenshotImagePayload {
        let response = try await screenshotRequest(
            request.requestID,
            kind: .image(itemID: request.itemID, revision: request.revision),
            .screenshotImageRequest(request)
        )
        guard case let .image(payload) = response else { throw Self.unexpectedScreenshotReply }
        return payload
    }
    func deleteScreenshots(_ request: RemoteScreenshotDeleteRequest) async throws -> RemoteScreenshotDeleteResult {
        let response = try await screenshotRequest(request.requestID, kind: .delete, .screenshotDeleteRequest(request))
        guard case let .deleted(result) = response else { throw Self.unexpectedScreenshotReply }
        return result
    }
    private func screenshotRequest(
        _ id: UUID,
        kind: RemoteScreenshotResponses.Kind,
        _ message: RemoteMessage
    ) async throws -> RemoteScreenshotResponse {
        guard protocolVersion.supportsScreenshotsRemote else { throw Self.screenshotsUpgradeRequired }
        let registration = await screenshotResponses.register(id, kind: kind)
        do {
            try await sendMessage(message)
            return try await registration.response()
        } catch {
            await screenshotResponses.cancel(id, token: registration.token)
            throw error
        }
    }
    private static let screenshotsUpgradeRequired = RemoteProtocolError(
        code: .upgradeRequired,
        message: "Screenshots require a newer OnlySwitch"
    )
    private static let unexpectedScreenshotReply = RemoteProtocolError(code: .invalidFrame, message: "Unexpected screenshot reply")
    func setSystemMonitorStreaming(_ enabled: Bool) async throws {
        guard protocolVersion.supportsSystemMonitorRemote else {
            throw RemoteProtocolError(
                code: .actionNotSupported,
                message: "System Monitor is unavailable on this Mac"
            )
        }
        try await sendMessage(.systemMonitorSubscriptionUpdate(enabled))
    }
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

    func fetchCodexUsage(_ request: RemoteCodexUsageRequest) async throws -> RemoteCodexUsageResult {
        guard protocolVersion.supportsCodexUsageRemote else {
            throw RemoteProtocolError(code: .upgradeRequired, message: "Update OnlySwitch on the selected Mac")
        }
        let registration = await codexUsageResponses.register(request.requestID)
        do {
            try await sendMessage(.codexUsageRequest(request))
            for try await result in registration.stream { return result }
            throw CancellationError()
        } catch {
            await codexUsageResponses.cancel(request.requestID, token: registration.token)
            throw error
        }
    }

    func fetchClaudeUsage(_ request: RemoteClaudeUsageRequest) async throws -> RemoteClaudeUsageResult {
        guard protocolVersion.supportsClaudeUsageRemote else {
            throw RemoteProtocolError(code: .upgradeRequired, message: "Update OnlySwitch on the selected Mac")
        }
        let registration = await claudeUsageResponses.register(request.requestID)
        do {
            try await sendMessage(.claudeUsageRequest(request))
            for try await result in registration.stream { return result }
            throw CancellationError()
        } catch {
            await claudeUsageResponses.cancel(request.requestID, token: registration.token)
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
        await codexUsageResponses.finishAll()
        await claudeUsageResponses.finishAll()
        await screenshotResponses.finishAll()
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
                if case let .codexUsageResult(result) = message { await codexUsageResponses.resolve(result) }
                if case let .claudeUsageResult(result) = message { await claudeUsageResponses.resolve(result) }
                if await screenshotResponses.consume(message) { continue }
                await event(message)
            }
        } catch is CancellationError {
        } catch {
            await actionResponses.finishAll()
            await codexUsageResponses.finishAll()
            await claudeUsageResponses.finishAll()
            await screenshotResponses.finishAll()
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
