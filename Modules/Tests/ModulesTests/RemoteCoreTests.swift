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
        #expect(RemoteProtocolVersion.current == .init(major: 1, minor: 8))
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
        #expect(RemoteProtocolVersion.current == .init(major: 1, minor: 8))
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
        #expect(RemoteProtocolVersion.current.supportsCodexUsageRemote)
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
        let future = RemoteProtocolVersion(major: 1, minor: 9)

        #expect(RemoteProtocolVersion.current == .init(major: 1, minor: 8))
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

    @Test func protocolOneEightEnablesSoundMixerTabAndBrightness() {
        #expect(RemoteProtocolVersion.current == .init(major: 1, minor: 8))
        #expect(RemoteProtocolVersion(major: 1, minor: 8).supportsSoundMixerTabRemote)
        #expect(RemoteProtocolVersion(major: 1, minor: 8).supportsBrightnessRemote)
        #expect(RemoteProtocolVersion(major: 1, minor: 7).supportsSoundMixerTabRemote == false)
        #expect(RemoteProtocolVersion(major: 1, minor: 7).supportsBrightnessRemote == false)
    }

    @Test func legacySoundMixerSnapshotDecodesWithDefaults() throws {
        let legacy = #"{"revision":3,"isEnabled":true,"systemVolume":40,"apps":[{"id":"a","name":"Music","volume":20,"isMuted":false}]}"#
        let snapshot = try JSONDecoder().decode(RemoteSoundMixerSnapshot.self, from: Data(legacy.utf8))
        #expect(snapshot.isSystemVolumeAvailable)
        #expect(snapshot.outputDevices.isEmpty)
        #expect(snapshot.apps[0].equalizer == nil)
        #expect(snapshot.apps[0].routing == nil)
    }

    @Test func soundMixerModelsClampAndBound() {
        let eq = RemoteSoundMixerEqualizer(gains: [99, -99, .nan], status: .active)
        #expect(eq.gains.count == 10)
        #expect(eq.gains[0] == 12)
        #expect(eq.gains[1] == -12)
        #expect(eq.gains[2] == 0)
        let routing = RemoteSoundMixerRouting(selectedDeviceIDs: (0..<40).map(String.init), status: .active)
        #expect(routing.selectedDeviceIDs.count == 16)
        let snapshot = RemoteSoundMixerSnapshot(
            revision: 1, isEnabled: true, systemVolume: 50, output: nil, apps: [],
            isSystemVolumeAvailable: true,
            outputDevices: (0..<50).map { .init(id: "\($0)", name: "D", isDefault: false) }
        )
        #expect(snapshot.outputDevices.count == 32)
        #expect(RemoteSoundMixerApp.clampVolume(140) == 100)
        #expect(RemoteSoundMixerApp.clampVolume(-3) == 0)
        #expect(RemoteSoundMixerApp.clampVolume(.infinity) == 0)
    }

    @Test func soundMixerSnapshotDecodingAppliesBoundsAndToleratesUnknownStatus() throws {
        let devices = (0..<40).map { #"{"id":"d\#($0)","name":"D","isDefault":false}"# }.joined(separator: ",")
        let json = #"{"revision":1,"isEnabled":true,"systemVolume":400,"isSystemVolumeAvailable":false,"outputDevices":["# + devices + #"],"apps":[{"id":"a","name":"Music","volume":20,"isMuted":false,"equalizer":{"gains":[30],"status":"futureStatus"},"routing":{"selectedDeviceIDs":["d1"],"status":"futureStatus"}}]}"#
        let snapshot = try JSONDecoder().decode(RemoteSoundMixerSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.systemVolume == 100)
        #expect(snapshot.isSystemVolumeAvailable == false)
        #expect(snapshot.outputDevices.count == 32)
        #expect(snapshot.apps[0].equalizer == .init(gains: [12], status: .unavailable))
        #expect(snapshot.apps[0].routing == .init(selectedDeviceIDs: ["d1"], status: .unavailable))
    }

    @Test func soundMixerSnapshotContentComparisonIgnoresRevision() {
        func snapshot(revision: UInt64, volume: Double = 30) -> RemoteSoundMixerSnapshot {
            RemoteSoundMixerSnapshot(
                revision: revision, isEnabled: true, systemVolume: volume,
                output: .init(name: "Speakers", symbolName: "speaker.wave.2"),
                apps: [.init(id: "a", name: "Music", volume: 20, isMuted: false,
                             equalizer: .init(gains: [1], status: .active),
                             routing: .init(selectedDeviceIDs: ["d"], status: .active))],
                isSystemVolumeAvailable: true,
                outputDevices: [.init(id: "d", name: "Speakers", isDefault: true)]
            )
        }
        #expect(snapshot(revision: 1).hasSameContent(as: snapshot(revision: 9)))
        #expect(snapshot(revision: 1) != snapshot(revision: 9))
        #expect(snapshot(revision: 1).hasSameContent(as: snapshot(revision: 1, volume: 31)) == false)
    }

    @Test func soundMixerTabCommandsAreMarked() {
        #expect(RemoteSoundMixerCommand.setSystemVolume(1).requiresSoundMixerTab == false)
        #expect(RemoteSoundMixerCommand.setAppMuted(id: "a", isMuted: true).requiresSoundMixerTab == false)
        #expect(RemoteSoundMixerCommand.setAppEqualizerGain(id: "a", band: 0, gain: 1).requiresSoundMixerTab)
        #expect(RemoteSoundMixerCommand.resetAppEqualizer(id: "a").requiresSoundMixerTab)
        #expect(RemoteSoundMixerCommand.toggleAppOutputDevice(id: "a", deviceID: "d").requiresSoundMixerTab)
        #expect(RemoteSoundMixerCommand.followSystemOutput(id: "a").requiresSoundMixerTab)
    }

    @Test func brightnessModelsClamp() throws {
        let display = RemoteBrightnessDisplay(id: 1, name: String(repeating: "x", count: 500), control: .ddc, level: 4, hasError: false)
        #expect(display.level == 1)
        #expect(display.name.count == 120)
        let snapshot = RemoteBrightnessSnapshot(revision: 1, displays: Array(repeating: display, count: 30))
        #expect(snapshot.displays.count == 16)
        let json = #"{"id":3,"name":"Studio","control":"futureControl","level":-2}"#
        let decoded = try JSONDecoder().decode(RemoteBrightnessDisplay.self, from: Data(json.utf8))
        #expect(decoded == .init(id: 3, name: "Studio", control: .unavailable, level: 0, hasError: false))
    }

    @Test func newMessagesRoundTrip() throws {
        let messages: [RemoteMessage] = [
            .soundMixerSubscriptionUpdate(true),
            .brightnessSubscriptionUpdate(false),
            .brightnessSnapshot(.init(revision: 2, displays: [.init(id: 7, name: "Studio", control: .native, level: 0.5, hasError: false)])),
            .brightnessCommand(.setLevel(displayID: 7, level: 0.25)),
            .soundMixerCommand(.setAppEqualizerGain(id: "a", band: 3, gain: -4)),
            .soundMixerCommand(.resetAppEqualizer(id: "a")),
            .soundMixerCommand(.toggleAppOutputDevice(id: "a", deviceID: "d")),
            .soundMixerCommand(.followSystemOutput(id: "a")),
        ]
        for message in messages {
            let data = try JSONEncoder().encode(message)
            #expect(try JSONDecoder().decode(RemoteMessage.self, from: data) == message)
        }
    }
}
