import Foundation
import RemoteCore
import Security
import Testing
@testable import OnlySwitchRemote

struct RemotePersistenceClientTests {
    private let firstMac = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let secondMac = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test func layoutsRemainIndependentPerMac() async throws {
        let client = RemotePersistenceClient.inMemory()
        try await client.saveLayout(.init(macID: firstMac, selectedControlIDs: [.darkMode], order: [.darkMode]))
        try await client.saveLayout(.init(macID: secondMac, selectedControlIDs: [.mute], order: [.mute]))

        #expect(try await client.loadLayout(firstMac)?.selectedControlIDs == [.darkMode])
        #expect(try await client.loadLayout(secondMac)?.selectedControlIDs == [.mute])
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
            delete: { [weak self] _ in await self?.delete() ?? errSecNotAvailable }
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
}
