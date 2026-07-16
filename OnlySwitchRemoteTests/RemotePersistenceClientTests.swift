import Foundation
import RemoteCore
import Security
import Testing
@testable import OnlySwitchRemote

struct RemotePersistenceClientTests {
    private let firstMac = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let secondMac = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test func legacyStateMigratesIntoOneEnvelope() async throws {
        let harness = try AtomicEnvelopeHarness.make()
        let mac = PairedMac(
            id: firstMac,
            displayName: "Studio",
            lastEndpointDescription: nil,
            lastConnectedAt: nil,
            requiresPairing: false
        )
        harness.defaults.set(try JSONEncoder().encode([mac]), forKey: "pairedMacs")
        harness.defaults.set(mac.id.uuidString, forKey: "selectedMacID")
        harness.defaults.set(true, forKey: RemotePersistenceClient.initialSetupCompletedKey)

        let envelope = try await harness.store.loadEnvelope()

        #expect(envelope.version == 1)
        #expect(envelope.pairedMacs == [mac])
        #expect(envelope.selectedMacID == mac.id)
        #expect(envelope.hasCompletedInitialSetup)
        #expect(try Data(contentsOf: harness.envelopeURL).isEmpty == false)
        #expect(harness.defaults.integer(forKey: "remoteStateEnvelopeMigrationVersion") == 1)
    }

    @Test func failedLegacyMigrationPreservesSourceAndCanRetry() async throws {
        let harness = try AtomicEnvelopeHarness.make()
        let mac = PairedMac(
            id: firstMac,
            displayName: "Studio",
            lastEndpointDescription: nil,
            lastConnectedAt: nil,
            requiresPairing: false
        )
        let legacyData = try JSONEncoder().encode([mac])
        harness.defaults.set(legacyData, forKey: "pairedMacs")
        harness.defaults.set(mac.id.uuidString, forKey: "selectedMacID")
        harness.failNextReplacement()

        await #expect(throws: (any Error).self) {
            try await harness.store.loadEnvelope()
        }
        #expect(harness.defaults.data(forKey: "pairedMacs") == legacyData)
        #expect(harness.defaults.string(forKey: "selectedMacID") == mac.id.uuidString)
        #expect(harness.defaults.integer(forKey: "remoteStateEnvelopeMigrationVersion") == 0)
        #expect(FileManager.default.fileExists(atPath: harness.envelopeURL.path) == false)

        let envelope = try await harness.store.loadEnvelope()
        #expect(envelope.pairedMacs == [mac])
        #expect(envelope.selectedMacID == mac.id)
        #expect(harness.defaults.integer(forKey: "remoteStateEnvelopeMigrationVersion") == 1)
    }

    @Test func pairingPrepareAndRestoreAreSingleAtomicReplacements() async throws {
        let harness = try AtomicEnvelopeHarness.make()
        let old = PairedMac(
            id: firstMac,
            displayName: "Old",
            lastEndpointDescription: nil,
            lastConnectedAt: nil,
            requiresPairing: false
        )
        let candidate = PairedMac(
            id: secondMac,
            displayName: "New",
            lastEndpointDescription: nil,
            lastConnectedAt: nil,
            requiresPairing: false
        )
        try await harness.store.saveEnvelope(.init(
            pairedMacs: [old],
            selectedMacID: old.id,
            hasCompletedInitialSetup: true
        ))
        let bytesBeforePrepare = try Data(contentsOf: harness.envelopeURL)
        harness.failNextReplacement()

        await #expect(throws: (any Error).self) {
            try await harness.store.preparePairingState(
                candidate,
                transactionID: UUID(),
                credentialIdentity: Data(repeating: 8, count: 32)
            )
        }
        #expect(try Data(contentsOf: harness.envelopeURL) == bytesBeforePrepare)

        let prepared = try await harness.store.preparePairingState(
            candidate,
            transactionID: UUID(),
            credentialIdentity: Data(repeating: 8, count: 32)
        )
        #expect(try await harness.store.loadEnvelope().selectedMacID == candidate.id)
        let bytesBeforeRestore = try Data(contentsOf: harness.envelopeURL)
        harness.failNextReplacement()
        await #expect(throws: (any Error).self) {
            try await harness.store.restorePairingState(prepared)
        }
        #expect(try Data(contentsOf: harness.envelopeURL) == bytesBeforeRestore)

        try await harness.store.restorePairingState(prepared)
        let restored = try await harness.store.loadEnvelope()
        #expect(restored.selectedMacID == old.id)
        #expect(restored.pairedMacs == [old])
        #expect(restored.preparedPairing == nil)
    }

    @Test func pairingFinalizeIsOneAtomicReplacement() async throws {
        let harness = try AtomicEnvelopeHarness.make()
        let candidate = PairedMac(
            id: secondMac,
            displayName: "New",
            lastEndpointDescription: nil,
            lastConnectedAt: nil,
            requiresPairing: false
        )
        let transactionID = UUID()
        _ = try await harness.store.preparePairingState(
            candidate,
            transactionID: transactionID,
            credentialIdentity: Data(repeating: 9, count: 32)
        )
        let bytesBeforeFinalize = try Data(contentsOf: harness.envelopeURL)
        harness.failNextReplacement()

        await #expect(throws: (any Error).self) {
            try await harness.store.finalizePairingState(transactionID)
        }
        #expect(try Data(contentsOf: harness.envelopeURL) == bytesBeforeFinalize)

        try await harness.store.finalizePairingState(transactionID)
        let finalized = try await harness.store.loadEnvelope()
        #expect(finalized.selectedMacID == candidate.id)
        #expect(finalized.pairedMacs == [candidate])
        #expect(finalized.preparedPairing == nil)
    }

    @Test func initialSetupCompletionRoundTripsWithoutAmbientDefaults() async throws {
        let client = RemotePersistenceClient.inMemory()
        #expect(try await client.loadInitialSetupCompleted() == false)
        try await client.saveInitialSetupCompleted(true)
        #expect(try await client.loadInitialSetupCompleted())
    }

    @Test func synchronousLaunchSeedUsesInjectedDefaults() throws {
        let suite = "InitialSetupSeed-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(RemotePersistenceClient.initialSetupSeed(defaults: defaults) == false)
        defaults.set(true, forKey: RemotePersistenceClient.initialSetupCompletedKey)
        #expect(RemotePersistenceClient.initialSetupSeed(defaults: defaults))
    }

    @Test func layoutsRemainIndependentPerMac() async throws {
        let client = RemotePersistenceClient.inMemory()
        try await client.saveLayout(.init(macID: firstMac, selectedControlIDs: [.darkMode], order: [.darkMode]))
        try await client.saveLayout(.init(macID: secondMac, selectedControlIDs: [.mute], order: [.mute]))

        #expect(try await client.loadLayout(firstMac)?.selectedControlIDs == [.darkMode])
        #expect(try await client.loadLayout(secondMac)?.selectedControlIDs == [.mute])
    }

    @Test func tombstoneRejectsLateWritesUntilPairCommitAtomicallyClearsIt() async throws {
        let client = RemotePersistenceClient.inMemory()
        let old = PairedMac(id: firstMac, displayName: "Old", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
        let replacement = PairedMac(id: firstMac, displayName: "New", lastEndpointDescription: nil, lastConnectedAt: .now, requiresPairing: false)
        try await client.upsertPairedMac(old)
        try await client.markMacTombstoned(firstMac)

        try await client.saveLayout(.init(macID: firstMac, selectedControlIDs: [.mute], order: [.mute]))
        try await client.saveCatalog(firstMac, 9, [])
        try await client.mergeStatus(firstMac, status(id: .mute, isOn: true, revision: 9))
        try await client.upsertPairedMac(old)

        #expect(try await client.loadLayout(firstMac) == nil)
        #expect(try await client.loadCatalog(firstMac) == nil)
        #expect(try await client.loadStatuses(firstMac) == nil)
        #expect(try await client.loadPairedMacs() == [old])

        try await client.commitPairing(replacement)
        try await client.saveLayout(.init(macID: firstMac, selectedControlIDs: [.mute], order: [.mute]))
        #expect(try await client.loadPairedMacs() == [replacement])
        #expect(try await client.loadLayout(firstMac)?.order == [.mute])
    }

    @Test func pairingTransactionAtomicallySelectsCandidateAndRestoresPreviousSelection() async throws {
        let client = RemotePersistenceClient.inMemory()
        let first = PairedMac(id: firstMac, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
        let second = PairedMac(id: secondMac, displayName: "Laptop", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
        try await client.commitPairing(first)
        try await client.saveSelectedMacID(firstMac)

        let snapshot = try await client.commitPairingAndSelect(second)
        #expect(snapshot.previousSelectedMacID == firstMac)
        #expect(try await client.loadSelectedMacID() == secondMac)
        #expect(Set(try await client.loadPairedMacs().map(\.id)) == [firstMac, secondMac])

        try await client.restorePairingSnapshot(secondMac, snapshot)
        #expect(try await client.loadSelectedMacID() == firstMac)
        #expect(try await client.loadPairedMacs() == [first])
    }

    @Test func pairingTransactionRollbackRestoresCandidateTombstone() async throws {
        let client = RemotePersistenceClient.inMemory()
        let candidate = PairedMac(id: secondMac, displayName: "Laptop", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
        try await client.markMacTombstoned(secondMac)

        let snapshot = try await client.commitPairingAndSelect(candidate)
        #expect(await client.isMacTombstoned(secondMac) == false)
        try await client.restorePairingSnapshot(secondMac, snapshot)

        #expect(await client.isMacTombstoned(secondMac))
        #expect(try await client.loadPairedMacs().isEmpty)
        #expect(try await client.loadSelectedMacID() == nil)
    }

    @Test func fileBackedTombstonePreventsLateCacheWritesFromRecreatingMacDirectory() async throws {
        let suite = "RemotePersistenceTombstoneTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RemoteFilePersistenceStore(defaultsSuiteName: suite, rootURL: root)
        let client = RemotePersistenceClient.fileBacked(store: store, keychain: .inMemory())
        let directory = root.appendingPathComponent(firstMac.uuidString.lowercased(), isDirectory: true)

        try await client.markMacTombstoned(firstMac)
        try await client.saveLayout(.init(macID: firstMac, selectedControlIDs: [.mute], order: [.mute]))
        try await client.saveCatalog(firstMac, 4, [])
        try await client.saveStatuses(firstMac, [status(id: .mute, isOn: true, revision: 4)])
        try await client.mergeStatus(firstMac, status(id: .mute, isOn: false, revision: 5))

        #expect(FileManager.default.fileExists(atPath: directory.path) == false)
        #expect(try await client.loadLayout(firstMac) == nil)
        #expect(try await client.loadCatalog(firstMac) == nil)
        #expect(try await client.loadStatuses(firstMac) == nil)
    }

    @Test func forgettingOneMacPreservesOtherMacData() async throws {
        let client = RemotePersistenceClient.inMemory()
        try await client.savePairedMacs([
            .init(id: firstMac, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false),
            .init(id: secondMac, displayName: "Laptop", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false),
        ])
        try await client.saveLayout(.init(macID: firstMac, selectedControlIDs: [.darkMode], order: [.darkMode]))
        try await client.saveLayout(.init(macID: secondMac, selectedControlIDs: [.mute], order: [.mute]))
        try await client.saveSelectedMacID(firstMac)

        try await client.forgetMac(firstMac)

        #expect(try await client.loadPairedMacs().map(\.id) == [secondMac])
        #expect(try await client.loadLayout(firstMac) == nil)
        #expect(try await client.loadLayout(secondMac)?.selectedControlIDs == [.mute])
        #expect(try await client.loadSelectedMacID() == nil)
    }

    @Test func keychainRejectsCredentialsThatAreNotThirtyTwoBytes() async {
        let keychain = RemoteKeychainClient.inMemory()

        await #expect(throws: RemoteKeychainClient.Error.invalidCredentialLength) {
            try await keychain.saveCredential(firstMac, Data(repeating: 7, count: 31))
        }
        let stored = try? await keychain.loadCredential(firstMac)
        #expect(stored == nil)
    }

    @Test func keychainUpdateFailureNeverDeletesExistingCredential() async {
        let recorder = KeychainOperationRecorder(stored: Data(repeating: 1, count: 32), updateStatus: errSecInteractionNotAllowed)
        let client = RemoteKeychainClient.live(operations: recorder.operations)

        await #expect(throws: RemoteKeychainClient.Error.status(errSecInteractionNotAllowed)) {
            try await client.saveCredential(firstMac, Data(repeating: 2, count: 32))
        }

        #expect(await recorder.stored == Data(repeating: 1, count: 32))
        #expect(await recorder.addCount == 0)
        #expect(await recorder.deleteCount == 0)
    }

    @Test func keychainAddFailureAfterItemNotFoundDoesNotDelete() async {
        let recorder = KeychainOperationRecorder(stored: nil, updateStatus: errSecItemNotFound, addStatus: errSecNotAvailable)
        let client = RemoteKeychainClient.live(operations: recorder.operations)

        await #expect(throws: RemoteKeychainClient.Error.status(errSecNotAvailable)) {
            try await client.saveCredential(firstMac, Data(repeating: 2, count: 32))
        }

        #expect(await recorder.stored == nil)
        #expect(await recorder.addCount == 1)
        #expect(await recorder.deleteCount == 0)
    }

    @Test func conditionalCredentialDeletePreservesReplacement() async throws {
        let keychain = RemoteKeychainClient.inMemory()
        let oldCredential = Data(repeating: 1, count: 32)
        let replacement = Data(repeating: 2, count: 32)
        try await keychain.saveCredential(firstMac, replacement)

        #expect(try await keychain.deleteCredentialIfMatches(firstMac, oldCredential) == false)
        #expect(try await keychain.loadCredential(firstMac) == replacement)
        #expect(try await keychain.deleteCredentialIfMatches(firstMac, replacement))
        #expect(try await keychain.loadCredential(firstMac) == nil)
    }

    @Test func statusMergePreservesOtherStatusesAndCatalogRevision() async throws {
        let client = RemotePersistenceClient.inMemory()
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
        let oldDarkMode = status(id: .darkMode, isOn: false, revision: 1)
        let mute = status(id: .mute, isOn: true, revision: 1)
        let newDarkMode = status(id: .darkMode, isOn: true, revision: 2)
        try await client.saveCatalog(firstMac, 17, [descriptor])
        try await client.saveStatuses(firstMac, [oldDarkMode, mute])

        try await client.mergeStatus(firstMac, newDarkMode)

        #expect(try await client.loadCatalog(firstMac)?.revision == 17)
        let statuses = try #require(try await client.loadStatuses(firstMac))
        #expect(Set(statuses.map(\.id)) == [.darkMode, .mute])
        #expect(statuses.first(where: { $0.id == .darkMode })?.revision == 2)
        #expect(statuses.first(where: { $0.id == .mute })?.isOn == true)
    }

    @Test func olderStatusRevisionCannotOverwriteNewerCache() async throws {
        let client = RemotePersistenceClient.inMemory()
        try await client.mergeStatus(firstMac, status(id: .darkMode, isOn: true, revision: 9))

        try await client.mergeStatus(firstMac, status(id: .darkMode, isOn: false, revision: 8))

        let cached = try #require(try await client.loadStatuses(firstMac)?.first)
        #expect(cached.revision == 9)
        #expect(cached.isOn == true)
    }

    @Test func olderStatusSnapshotCannotOverwriteNewerCachedRevision() async throws {
        let client = RemotePersistenceClient.inMemory()
        try await client.saveStatuses(firstMac, [status(id: .darkMode, isOn: true, revision: 12)])

        try await client.saveStatuses(firstMac, [status(id: .darkMode, isOn: false, revision: 11)])

        let cached = try #require(try await client.loadStatuses(firstMac)?.first)
        #expect(cached.revision == 12)
        #expect(cached.isOn == true)
    }

    @Test func newSessionSnapshotReplacesHigherRevisionCache() async throws {
        let client = RemotePersistenceClient.inMemory()
        try await client.saveStatuses(firstMac, [status(id: .darkMode, isOn: false, revision: 99)])

        try await client.replaceStatusSnapshot(firstMac, [status(id: .darkMode, isOn: true, revision: 1)])

        let cached = try #require(try await client.loadStatuses(firstMac)?.first)
        #expect(cached.revision == 1)
        #expect(cached.isOn == true)
    }

    @Test func sharedStoreAtomicUpsertsDoNotClobberDifferentMacs() async throws {
        let suite = "RemotePersistenceAtomicTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RemoteFilePersistenceStore(defaultsSuiteName: suite, rootURL: root)
        let firstClient = RemotePersistenceClient.fileBacked(store: store, keychain: .inMemory())
        let secondClient = RemotePersistenceClient.fileBacked(store: store, keychain: .inMemory())
        let gate = PersistenceOperationGate(expected: 2)
        let first = PairedMac(id: firstMac, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
        let second = PairedMac(id: secondMac, displayName: "Laptop", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)

        async let firstWrite: Void = gate.arriveAndWait { try await firstClient.upsertPairedMac(first) }
        async let secondWrite: Void = gate.arriveAndWait { try await secondClient.upsertPairedMac(second) }
        _ = try await (firstWrite, secondWrite)

        #expect(Set(try await firstClient.loadPairedMacs().map(\.id)) == [firstMac, secondMac])
    }

    @Test func concurrentAtomicRemoveAndUpsertCannotResurrectOrClobberMacs() async throws {
        let suite = "RemotePersistenceRemoveTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RemoteFilePersistenceStore(defaultsSuiteName: suite, rootURL: root)
        let client = RemotePersistenceClient.fileBacked(store: store, keychain: .inMemory())
        try await client.upsertPairedMac(.init(
            id: firstMac,
            displayName: "Studio",
            lastEndpointDescription: nil,
            lastConnectedAt: nil,
            requiresPairing: false
        ))
        let gate = PersistenceOperationGate(expected: 2)
        let second = PairedMac(id: secondMac, displayName: "Laptop", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)

        async let removal: Void = gate.arriveAndWait { try await client.removePairedMac(firstMac) }
        async let upsert: Void = gate.arriveAndWait { try await client.upsertPairedMac(second) }
        _ = try await (removal, upsert)

        #expect(try await client.loadPairedMacs().map(\.id) == [secondMac])
    }

    @Test func partialForgetKeepsRecoverablePreferencesAndRetryIsIdempotent() async throws {
        let suite = "RemotePersistenceClientTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let keychain = RemoteKeychainClient.inMemory()
        try await keychain.saveCredential(firstMac, Data(repeating: 1, count: 32))
        let failingStore = RemoteFilePersistenceStore(
            defaultsSuiteName: suite,
            rootURL: root,
            removeDirectory: { _ in throw TestStorageError.cannotRemoveCache }
        )
        let failing = RemotePersistenceClient.fileBacked(store: failingStore, keychain: keychain)
        let first = PairedMac(id: firstMac, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
        let second = PairedMac(id: secondMac, displayName: "Laptop", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
        try await failing.savePairedMacs([first, second])
        try await failing.saveSelectedMacID(firstMac)
        try await failing.saveLayout(.init(macID: firstMac, selectedControlIDs: [.darkMode], order: [.darkMode]))

        await #expect(throws: TestStorageError.cannotRemoveCache) {
            try await failing.forgetMac(firstMac)
        }
        #expect(try await failing.loadPairedMacs().map(\.id) == [firstMac, secondMac])
        #expect(try await failing.loadSelectedMacID() == firstMac)
        #expect(try await keychain.loadCredential(firstMac) == nil)

        let retry = RemotePersistenceClient.fileBacked(
            store: RemoteFilePersistenceStore(defaultsSuiteName: suite, rootURL: root),
            keychain: keychain
        )
        try await retry.forgetMac(firstMac)
        try await retry.forgetMac(firstMac)
        #expect(try await retry.loadPairedMacs().map(\.id) == [secondMac])
        #expect(try await retry.loadSelectedMacID() == nil)
    }

    @Test func olderAppStateCannotOverwriteNewerClearedStateWhenDeliveredLast() async throws {
        let client = RemotePersistenceClient.inMemory()
        let writerID = UUID()
        let older = RemoteAppPersistenceIntent(
            writerID: writerID,
            sequence: 1,
            selectedMacID: firstMac,
            hasCompletedInitialSetup: true
        )
        let newer = RemoteAppPersistenceIntent(
            writerID: writerID,
            sequence: 2,
            selectedMacID: nil,
            hasCompletedInitialSetup: false
        )

        try await client.saveAppState(newer)
        try await client.saveAppState(older)

        #expect(try await client.loadSelectedMacID() == nil)
        #expect(try await client.loadInitialSetupCompleted() == false)
    }

    @Test func olderClearedStateCannotOverwriteNewerSelectedStateWhenDeliveredLast() async throws {
        let client = RemotePersistenceClient.inMemory()
        let writerID = UUID()
        let older = RemoteAppPersistenceIntent(
            writerID: writerID,
            sequence: 41,
            selectedMacID: nil,
            hasCompletedInitialSetup: false
        )
        let newer = RemoteAppPersistenceIntent(
            writerID: writerID,
            sequence: 42,
            selectedMacID: secondMac,
            hasCompletedInitialSetup: true
        )

        try await client.saveAppState(newer)
        try await client.saveAppState(older)

        #expect(try await client.loadSelectedMacID() == secondMac)
        #expect(try await client.loadInitialSetupCompleted())
    }

    @Test func sameSequenceRetryAfterInjectedFailureIsIdempotent() async throws {
        let failure = AtomicSaveFailure()
        let client = RemotePersistenceClient.inMemory { _ in
            try failure.failFirstAttempt()
        }
        let intent = RemoteAppPersistenceIntent(
            writerID: UUID(),
            sequence: 9,
            selectedMacID: firstMac,
            hasCompletedInitialSetup: true
        )

        await #expect(throws: AtomicSaveTestError.failed) {
            try await client.saveAppState(intent)
        }
        try await client.saveAppState(intent)
        try await client.saveAppState(intent)

        #expect(try await client.loadSelectedMacID() == firstMac)
        #expect(try await client.loadInitialSetupCompleted())
    }

    @Test func sharedFileStoreOrdersAtomicAppStateAcrossClients() async throws {
        let suite = "AtomicAppState-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RemoteFilePersistenceStore(defaultsSuiteName: suite, rootURL: root)
        let firstClient = RemotePersistenceClient.fileBacked(store: store, keychain: .inMemory())
        let secondClient = RemotePersistenceClient.fileBacked(store: store, keychain: .inMemory())
        let writerID = UUID()
        let older = RemoteAppPersistenceIntent(
            writerID: writerID,
            sequence: 3,
            selectedMacID: firstMac,
            hasCompletedInitialSetup: true
        )
        let newer = RemoteAppPersistenceIntent(
            writerID: writerID,
            sequence: 4,
            selectedMacID: nil,
            hasCompletedInitialSetup: false
        )

        try await secondClient.saveAppState(newer)
        try await firstClient.saveAppState(older)

        #expect(try await firstClient.loadSelectedMacID() == nil)
        #expect(try await secondClient.loadInitialSetupCompleted() == false)
    }

    private func status(id: RemoteControlID, isOn: Bool, revision: UInt64) -> RemoteControlStatus {
        .init(
            id: id,
            isAvailable: true,
            unavailableReason: nil,
            isOn: isOn,
            secondaryInformation: nil,
            isProcessing: false,
            revision: revision,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(revision))
        )
    }
}

private enum TestStorageError: Swift.Error, Equatable { case cannotRemoveCache }

private struct AtomicEnvelopeHarness {
    let defaultsSuiteName: String
    let rootURL: URL
    let replacementFailure: AtomicReplacementFailure
    let store: RemoteFilePersistenceStore

    var defaults: UserDefaults { UserDefaults(suiteName: defaultsSuiteName)! }
    var envelopeURL: URL { rootURL.appendingPathComponent("state-envelope-v1.json") }

    static func make() throws -> Self {
        let suite = "AtomicEnvelopeHarness-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let failure = AtomicReplacementFailure()
        let store = RemoteFilePersistenceStore(
            defaults: defaults,
            rootURL: rootURL,
            replaceEnvelope: { temporaryURL, envelopeURL in
                try failure.check()
                if FileManager.default.fileExists(atPath: envelopeURL.path) {
                    _ = try FileManager.default.replaceItemAt(envelopeURL, withItemAt: temporaryURL)
                } else {
                    try FileManager.default.moveItem(at: temporaryURL, to: envelopeURL)
                }
            }
        )
        return Self(defaultsSuiteName: suite, rootURL: rootURL, replacementFailure: failure, store: store)
    }

    func failNextReplacement() { replacementFailure.failNext() }
}

private enum AtomicReplacementTestError: Swift.Error { case failed }

private final class AtomicReplacementFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFail = false

    func failNext() {
        lock.lock()
        shouldFail = true
        lock.unlock()
    }

    func check() throws {
        lock.lock()
        defer { lock.unlock() }
        guard shouldFail else { return }
        shouldFail = false
        throw AtomicReplacementTestError.failed
    }
}

private enum AtomicSaveTestError: Swift.Error, Equatable { case failed }

private final class AtomicSaveFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFail = true

    func failFirstAttempt() throws {
        lock.lock()
        defer { lock.unlock() }
        guard shouldFail else { return }
        shouldFail = false
        throw AtomicSaveTestError.failed
    }
}

private actor PersistenceOperationGate {
    private let expected: Int
    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(expected: Int) { self.expected = expected }

    func arriveAndWait(_ operation: @Sendable () async throws -> Void) async throws {
        arrivals += 1
        if arrivals == expected {
            let current = waiters
            waiters.removeAll()
            for waiter in current { waiter.resume() }
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
        try await operation()
    }
}

private actor KeychainOperationRecorder {
    private(set) var stored: Data?
    private(set) var addCount = 0
    private(set) var deleteCount = 0
    let updateStatus: OSStatus
    let addStatus: OSStatus

    init(stored: Data?, updateStatus: OSStatus, addStatus: OSStatus = errSecSuccess) {
        self.stored = stored
        self.updateStatus = updateStatus
        self.addStatus = addStatus
    }

    nonisolated var operations: RemoteKeychainOperations {
        RemoteKeychainOperations(
            update: { [weak self] _, data in await self?.update(data) ?? errSecNotAvailable },
            add: { [weak self] _, data in await self?.add(data) ?? errSecNotAvailable },
            load: { [weak self] _ in
                guard let self else { return (errSecNotAvailable, nil) }
                let value = await self.stored
                return value.map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil)
            },
            delete: { [weak self] _ in await self?.delete() ?? errSecNotAvailable },
            deleteIfMatches: { [weak self] _, expected in
                guard let self else { return (errSecNotAvailable, false) }
                return await self.delete(matching: expected)
            }
        )
    }

    private func update(_ data: Data) -> OSStatus {
        if updateStatus == errSecSuccess { stored = data }
        return updateStatus
    }

    private func add(_ data: Data) -> OSStatus {
        addCount += 1
        if addStatus == errSecSuccess { stored = data }
        return addStatus
    }

    private func delete() -> OSStatus {
        deleteCount += 1
        stored = nil
        return errSecSuccess
    }

    private func delete(matching expected: Data) -> (OSStatus, Bool) {
        guard stored == expected else { return (errSecSuccess, false) }
        stored = nil
        deleteCount += 1
        return (errSecSuccess, true)
    }
}
