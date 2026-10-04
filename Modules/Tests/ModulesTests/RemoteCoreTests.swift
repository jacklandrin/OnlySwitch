import Foundation
import RemoteTransport
import Testing
@testable import RemoteCore

struct RemoteCoreTests {
    @Test func controlIDRoundTrips() throws {
        let value = RemoteControlID(kind: .evolution, value: UUID().uuidString)
        #expect(try JSONDecoder().decode(RemoteControlID.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test func actionMessageRoundTrips() throws {
        let request = RemoteActionRequest(
            requestID: UUID(),
            controlID: .init(kind: .builtIn, value: "2"),
            action: .setState(true)
        )
        let message = RemoteMessage.actionRequest(request)
        #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
    }

    @Test func majorCompatibilityRejectsDifferentMajor() {
        #expect(!RemoteProtocolVersion.current.isCompatible(with: .init(major: 2, minor: 0)))
        #expect(RemoteProtocolVersion.current.isCompatible(with: .init(major: 1, minor: 7)))
    }

    @Test func transactionalPairingRequiresMinorTwo() {
        #expect(!RemoteProtocolVersion(major: 1, minor: 1).supportsTransactionalPairing)
        #expect(RemoteProtocolVersion(major: 1, minor: 2).supportsTransactionalPairing)
        #expect(RemoteProtocolVersion.current == .init(major: 1, minor: 5))
    }

    @Test func soundMixerRequiresProtocolMinorThree() throws {
        #expect(RemoteProtocolVersion(major: 1, minor: 2).supportsSoundMixerRemote == false)
        #expect(RemoteProtocolVersion.current.supportsSoundMixerRemote)
        let snapshot = RemoteSoundMixerSnapshot(
            revision: 4, isEnabled: true, systemVolume: 55,
            output: .init(name: "Speakers", symbolName: "speaker.wave.2"),
            apps: [.init(id: "music", name: "Music", volume: 23, isMuted: false)]
        )
        let message = RemoteMessage.soundMixerSnapshot(snapshot)
        #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
    }

    @Test func systemMonitorRequiresProtocolMinorFour() {
        #expect(RemoteProtocolVersion(major: 1, minor: 3).supportsSystemMonitorRemote == false)
        #expect(RemoteProtocolVersion.current == .init(major: 1, minor: 5))
        #expect(RemoteProtocolVersion.current.supportsSystemMonitorRemote)
    }

    @Test func systemMonitorMessagesRoundTrip() throws {
        let snapshot = SystemMonitorSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            cpuUsage: .available(0.42),
            memory: .available(.init(totalBytes: 16_000, usedBytes: 8_000)),
            disks: [.init(id: "root", name: "Macintosh HD", totalBytes: 1_000, usedBytes: 500)]
        )

        for message in [
            RemoteMessage.systemMonitorSubscriptionUpdate(true),
            .systemMonitorSubscriptionUpdate(false),
            .systemMonitorSnapshot(snapshot),
        ] {
            #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
        }
    }

    @Test func codexUsageContractRoundTripsWithoutCredentialBearingValues() throws {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
        let snapshot = RemoteCodexUsageSnapshot(
            account: .init(email: "person@example.com", plan: "Plus"),
            session: .init(remainingPercent: 71, resetAt: Date(timeIntervalSince1970: 1_800_000_100)),
            weekly: .init(remainingPercent: 42, resetAt: Date(timeIntervalSince1970: 1_800_100_000)),
            resetCredits: .available(count: 3, expiresAt: Date(timeIntervalSince1970: 1_800_200_000)),
            creditBalance: .available(remaining: 12.5, limit: 50, unit: "credits"),
            source: .oauth,
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
            activity: .init(
                dailyUsage: [.init(date: Date(timeIntervalSince1970: 1_799_900_000), tokenCount: 1_234)],
                isPartial: true
            )
        )
        let request = RemoteCodexUsageRequest(requestID: requestID, includeLocalActivity: true)
        let response = RemoteCodexUsageResult(requestID: requestID, result: .success(snapshot))

        for message in [RemoteMessage.codexUsageRequest(request), .codexUsageResult(response)] {
            let data = try JSONEncoder().encode(message)
            #expect(try JSONDecoder().decode(RemoteMessage.self, from: data) == message)
            let wire = String(decoding: data, as: UTF8.self)
            #expect(wire.contains("accessToken") == false)
            #expect(wire.contains("refreshToken") == false)
            #expect(wire.contains("cookie") == false)
            #expect(wire.contains("filesystem") == false)
        }
    }

    @Test(arguments: [
        CodexResetCreditsDTO.unavailable,
        .unlimited,
        .available(count: 2, expiresAt: nil),
    ])
    func codexResetCreditFormsRoundTrip(_ value: CodexResetCreditsDTO) throws {
        #expect(try JSONDecoder().decode(CodexResetCreditsDTO.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test(arguments: [
        CodexCreditBalanceDTO.unavailable,
        .unlimited,
        .available(remaining: 4.25, limit: nil, unit: "credits"),
    ])
    func codexCreditBalanceFormsRoundTrip(_ value: CodexCreditBalanceDTO) throws {
        #expect(try JSONDecoder().decode(CodexCreditBalanceDTO.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test func codexUsageFailureRoundTripsAndMalformedEnvelopesAreRejected() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000502")!
        let failure = RemoteCodexUsageResult(
            requestID: id,
            result: .failure(.init(code: .authenticationFailed, message: "Sign in to Codex on the selected Mac."))
        )
        #expect(try JSONDecoder().decode(RemoteCodexUsageResult.self, from: JSONEncoder().encode(failure)) == failure)

        let decoder = JSONDecoder()
        let both = Data(#"{"requestID":"\#(id.uuidString)","success":{},"failure":{"code":"authenticationFailed","message":"No"}}"#.utf8)
        let neither = Data(#"{"requestID":"\#(id.uuidString)"}"#.utf8)
        #expect(throws: DecodingError.self) { try decoder.decode(RemoteCodexUsageResult.self, from: both) }
        #expect(throws: DecodingError.self) { try decoder.decode(RemoteCodexUsageResult.self, from: neither) }
    }

    @Test func codexUsageRequiresProtocolMinorFive() {
        let legacy = RemoteProtocolVersion(major: 1, minor: 4)
        let current = RemoteProtocolVersion(major: 1, minor: 5)

        #expect(legacy.supportsCodexUsageRemote == false)
        #expect(current.supportsCodexUsageRemote)
        #expect(RemoteProtocolVersion.current == current)
        #expect(current.negotiated(with: legacy) == legacy)
    }

    @Test(arguments: [
        (rawValue: -1, expected: 0),
        (rawValue: 0, expected: 0),
        (rawValue: 49, expected: 49),
        (rawValue: 100, expected: 100),
        (rawValue: 101, expected: 100),
    ])
    func codexQuotaRemainingPercentIsClamped(_ input: (rawValue: Int, expected: Int)) {
        #expect(CodexQuotaWindowDTO(remainingPercent: input.rawValue, resetAt: nil).remainingPercent == input.expected)
    }

    @Test func provisionalTeardownAlonePreservesDurablePreparedTransaction() {
        #expect(RemotePairingTeardownPolicy.action(for: .provisional) == .preserveDurablePreparedTransaction)
        #expect(RemotePairingTeardownPolicy.action(for: .committing) == .performNormalCleanup)
        #expect(RemotePairingTeardownPolicy.action(for: .authenticated) == .performNormalCleanup)
        #expect(RemotePairingTeardownPolicy.action(for: .other) == .performNormalCleanup)
    }

    @Test func pairingTransactionMessagesRoundTrip() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000912")!
        let prepared = PairingPrepared(
            transactionID: id,
            macID: UUID(uuidString: "00000000-0000-0000-0000-000000000913")!,
            credential: Data(repeating: 7, count: 32),
            catalogRevision: 4,
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        for message in [
            RemoteMessage.pairingPrepared(prepared),
            .pairingCommit(.init(transactionID: id)),
            .pairingAbort(.init(transactionID: id)),
            .pairingStatusRequest(.init(transactionID: id)),
            .pairingStatus(.init(transactionID: id, state: .prepared)),
            .pairingCommitted(.init(transactionID: id)),
        ] {
            #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
        }
    }

    @Test func authenticatedRevocationMessageRoundTrips() throws {
        let message = RemoteMessage.credentialRevoked
        #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
    }

    @Test func offlineRevocationProofRoundTrips() throws {
        let proof = CredentialRevocationProof(deviceID: UUID(), proof: Data(repeating: 9, count: 32))
        let message = RemoteMessage.credentialRevocationProof(proof)

        #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
    }

    @Test func protocolMinorNegotiatesWithoutSendingNewMessagesToLegacyPeers() {
        let legacy = RemoteProtocolVersion(major: 1, minor: 0)
        let future = RemoteProtocolVersion(major: 1, minor: 5)

        #expect(RemoteProtocolVersion.current == .init(major: 1, minor: 5))
        #expect(RemoteProtocolVersion.current.negotiated(with: legacy) == legacy)
        #expect(legacy.supportsAuthenticatedRevocation == false)
        #expect(RemoteProtocolVersion.current.supportsAuthenticatedRevocation)
        #expect(RemoteProtocolVersion.current.negotiated(with: future) == .current)
        #expect(future.negotiated(with: RemoteProtocolVersion(major: 1, minor: 0)) == .init(major: 1, minor: 0))
        #expect(RemoteProtocolVersion.current.negotiated(with: .init(major: 2, minor: 0)) == nil)
    }

    @Test func offlineRevocationProofIsBoundToFreshHandshakeTranscript() {
        let credential = Data(repeating: 4, count: 32)
        let verifier = RemoteHandshakeCrypto.revocationVerifier(credential: credential)
        let firstTranscript = Data("first-fresh-transcript".utf8)
        let secondTranscript = Data("second-fresh-transcript".utf8)
        let proof = RemoteHandshakeCrypto.revocationProof(verifier: verifier, transcript: firstTranscript)

        #expect(verifier != credential)
        #expect(RemoteHandshakeCrypto.verifyRevocationProof(proof, verifier: verifier, transcript: firstTranscript))
        #expect(!RemoteHandshakeCrypto.verifyRevocationProof(proof, verifier: verifier, transcript: secondTranscript))
        #expect(!RemoteHandshakeCrypto.verifyRevocationProof(Data(repeating: 0, count: 32), verifier: verifier, transcript: firstTranscript))
    }
}
