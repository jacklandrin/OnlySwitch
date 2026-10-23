#if os(macOS)
import Foundation
import Testing
import Synchronization
@testable import XcodeCleaner

struct XcodeCleanerSimulatorTests {
    @Test func midBatchCancellationPreservesAlreadyDeletedDeviceAndScopesRemainingFailure() async throws {
        let secondID = "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"
        let runner = CleanerCancelAfterDelete(secondID: secondID)
        let adapter = XcodeCleanerSimulator(run: { await runner.run($0) })
        let snapshot = try await adapter.scan()
        let operation = Task {
            try await adapter.clean(.init(snapshotID: snapshot.id, itemIDs: ["device:\(cleanerDeviceID)", "device:\(secondID)"]))
        }
        let result = try await operation.value
        #expect(result.removedItemIDs == ["device:\(cleanerDeviceID)"])
        #expect(result.failures.contains { $0.itemID == "device:\(secondID)" })
        #expect(await runner.deletions == [["simctl", "delete", cleanerDeviceID]])
    }
    @Test func batchPreflightDoesNotRemeasureDevicesAndUsesOneInventoryPair() async throws {
        let fixture = try CleanerFixture(); defer { fixture.remove() }
        let measurements = Mutex(0)
        let runtimeJSON = """
        {"\(cleanerRuntimeImageID)":{"identifier":"\(cleanerRuntimeImageID)","runtimeIdentifier":"\(cleanerRuntimeIdentifier)","deletable":true,"sizeBytes":4096,"state":"Ready"}}
        """
        let recorder = CleanerCommandRecorder(deviceJSON: cleanerDevices(), runtimeJSON: runtimeJSON)
        let adapter = XcodeCleanerSimulator(home: fixture.home, measureDevice: { _ in measurements.withLock { $0 += 1 }; return 32 }, run: { try await recorder.run($0) })
        let snapshot = try await adapter.scan()
        #expect(snapshot.items.first { $0.category == .simulatorDevice }?.bytes == 32)
        #expect(measurements.withLock { $0 } == 1)
        let result = try await adapter.clean(.init(snapshotID: snapshot.id, itemIDs: ["device:\(cleanerDeviceID)", "runtime:\(cleanerRuntimeImageID)"]))
        #expect(Set(result.removedItemIDs) == ["device:\(cleanerDeviceID)", "runtime:\(cleanerRuntimeImageID)"])
        #expect(measurements.withLock { $0 } == 1)
        let commands = await recorder.commands
        #expect(commands.filter { $0.arguments == ["simctl", "list", "--json"] }.count == 2)
        #expect(commands.filter { $0.arguments == ["simctl", "runtime", "list", "--json"] }.count == 2)
    }

    @Test func simulatorDisplayedAuthorizationSurvivesNewInventory() async throws {
        let recorder = CleanerCommandRecorder(deviceJSON: cleanerDevices())
        let adapter = XcodeCleanerSimulator(run: { try await recorder.run($0) })
        let displayed = try await adapter.scan()
        await adapter.activateSnapshot(displayed.id)
        for _ in 0..<8 { _ = try await adapter.scan() }
        let result = try await adapter.clean(.init(snapshotID: displayed.id, itemIDs: ["device:\(cleanerDeviceID)"]))
        #expect(result.removedItemIDs == ["device:\(cleanerDeviceID)"])
    }

    @Test func deviceInventoryPreservesExplicitRuntimeMetadataAndUnavailableMembers() async throws {
        let ios = "com.apple.CoreSimulator.SimRuntime.iOS-27-1"
        let watch = "com.apple.CoreSimulator.SimRuntime.watchOS-27-1"
        let json = """
        {"devices":{"\(ios)":[{"udid":"\(cleanerDeviceID)","name":"Phone","state":"Shutdown","isAvailable":false}],"\(watch)":[{"udid":"BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF","name":"Watch","state":"Shutdown","isAvailable":true}]},"runtimes":[{"identifier":"\(ios)","name":"iOS 27.1"},{"identifier":"\(watch)","name":"watchOS 27.1"}]}
        """
        let recorder = CleanerCommandRecorder(deviceJSON: json)
        let snapshot = try await XcodeCleanerSimulator(run: { try await recorder.run($0) }).scan()
        let phone = try #require(snapshot.items.first { $0.title == "Phone" })
        let watchItem = try #require(snapshot.items.first { $0.title == "Watch" })
        #expect(phone.runtimeIdentifier == ios)
        #expect(phone.runtimeName == "iOS 27.1")
        #expect(phone.statusKey == "Unavailable")
        #expect(watchItem.runtimeIdentifier == watch)
        #expect(watchItem.runtimeName == "watchOS 27.1")
    }

    @Test func descriptorlessRuntimeKeepsIdentityWithoutInventingDisplayName() async throws {
        let json = """
        {"devices":{"\(cleanerRuntimeIdentifier)":[{"udid":"\(cleanerDeviceID)","name":"Phone","state":"Shutdown","isAvailable":true}]},"runtimes":[]}
        """
        let recorder = CleanerCommandRecorder(deviceJSON: json)
        let snapshot = try await XcodeCleanerSimulator(run: { try await recorder.run($0) }).scan()
        let item = try #require(snapshot.items.first { $0.category == .simulatorDevice })
        #expect(item.runtimeIdentifier == cleanerRuntimeIdentifier)
        #expect(item.runtimeName == nil)
        #expect(item.id == "device:\(cleanerDeviceID)")
    }

    @Test func inventoryRetainsUnavailableDevicesAndUnknownSize() async throws {
        let recorder = CleanerCommandRecorder(deviceJSON: cleanerDevices(available: false))
        let adapter = XcodeCleanerSimulator(run: { try await recorder.run($0) })
        let snapshot = try await adapter.scan()
        let item = try #require(snapshot.items.first { $0.category == .simulatorDevice })
        #expect(item.id == "device:\(cleanerDeviceID)")
        #expect(item.title == "Test iPhone")
        #expect(item.bytes == nil)
        #expect(item.requiresConfirmation)
    }

    @Test func deviceDeletionUsesOnlyValidatedUDIDArguments() async throws {
        let recorder = CleanerCommandRecorder(deviceJSON: cleanerDevices())
        let adapter = XcodeCleanerSimulator(run: { try await recorder.run($0) })
        let snapshot = try await adapter.scan()
        let item = try #require(snapshot.items.first { $0.category == .simulatorDevice })
        let result = try await adapter.clean(CleanerCleanupRequest(snapshotID: snapshot.id, itemIDs: [item.id]))
        #expect(result.failures.isEmpty)
        let commands = await recorder.deletionCommands
        #expect(commands.count == 1)
        #expect(commands.first?.executable.path == "/usr/bin/xcrun")
        #expect(commands.first?.arguments == ["simctl", "delete", cleanerDeviceID])
    }

    @Test func newlyBootedDeviceIsRejectedByFreshInventory() async throws {
        let recorder = CleanerCommandRecorder(deviceJSON: cleanerDevices())
        let adapter = XcodeCleanerSimulator(run: { try await recorder.run($0) })
        let snapshot = try await adapter.scan()
        let item = try #require(snapshot.items.first { $0.category == .simulatorDevice })
        await recorder.replaceDevices(cleanerDevices(state: "Booted"))
        let result = try await adapter.clean(CleanerCleanupRequest(snapshotID: snapshot.id, itemIDs: [item.id]))
        #expect(!result.failures.isEmpty)
        #expect(await recorder.deletionCommands.isEmpty)
    }

    @Test func runtimeDeletionUsesImageUUIDInsteadOfDescriptorIdentifier() async throws {
        let runtimeJSON = """
        {"\(cleanerRuntimeImageID)":{"identifier":"\(cleanerRuntimeImageID)","runtimeIdentifier":"\(cleanerRuntimeIdentifier)","runtimeBundlePath":"/Library/Developer/CoreSimulator/Volumes/iOS/Runtime.simruntime","deletable":true,"sizeBytes":4096,"state":"Ready","version":"27.1","build":"24B1"}}
        """
        let recorder = CleanerCommandRecorder(deviceJSON: cleanerDevices(), runtimeJSON: runtimeJSON)
        let adapter = XcodeCleanerSimulator(run: { try await recorder.run($0) })
        let snapshot = try await adapter.scan()
        let item = try #require(snapshot.items.first { $0.category == .simulatorRuntime && $0.canClean })
        #expect(item.id == "runtime:\(cleanerRuntimeImageID)")
        #expect(item.bytes == 4096)
        #expect(item.runtimeIdentifier == cleanerRuntimeIdentifier)
        #expect(item.runtimeName == "iOS 27.1")
        _ = try await adapter.clean(CleanerCleanupRequest(snapshotID: snapshot.id, itemIDs: [item.id]))
        #expect(await recorder.deletionCommands.first?.arguments == ["simctl", "runtime", "delete", cleanerRuntimeImageID])
    }

    @Test func untrustedIdentifierCannotBecomeDeleteCommand() async throws {
        let recorder = CleanerCommandRecorder(deviceJSON: cleanerDevices())
        let adapter = XcodeCleanerSimulator(run: { try await recorder.run($0) })
        let snapshot = try await adapter.scan()
        let result = try await adapter.clean(CleanerCleanupRequest(snapshotID: snapshot.id, itemIDs: ["device:$(touch /tmp/no); delete all"]))
        #expect(!result.failures.isEmpty)
        #expect(await recorder.deletionCommands.isEmpty)
    }

    @Test(arguments: ["not JSON", "{}", "{\"devices\":[]}"])
    func malformedOrUnsupportedInventoryIsVisible(json: String) async throws {
        let recorder = CleanerCommandRecorder(deviceJSON: json)
        let snapshot = try await XcodeCleanerSimulator(run: { try await recorder.run($0) }).scan()
        #expect(!snapshot.failures.isEmpty)
        #expect(snapshot.items.filter { $0.category == .simulatorDevice }.isEmpty)
    }

    @Test func commandFailureDoesNotLookLikeEmptySuccess() async throws {
        let recorder = CleanerCommandRecorder(deviceJSON: cleanerDevices())
        await recorder.setInventoryFailure()
        let snapshot = try await XcodeCleanerSimulator(run: { try await recorder.run($0) }).scan()
        #expect(!snapshot.failures.isEmpty)
        #expect(await recorder.deletionCommands.isEmpty)
    }

    @Test func runtimeMarkedNondeletableNeverRunsDelete() async throws {
        let runtimeJSON = """
        {"\(cleanerRuntimeImageID)":{"identifier":"\(cleanerRuntimeImageID)","runtimeIdentifier":"\(cleanerRuntimeIdentifier)","deletable":false,"sizeBytes":4096,"state":"Ready"}}
        """
        let recorder = CleanerCommandRecorder(deviceJSON: cleanerDevices(), runtimeJSON: runtimeJSON)
        let adapter = XcodeCleanerSimulator(run: { try await recorder.run($0) })
        let snapshot = try await adapter.scan()
        #expect(snapshot.items.filter { $0.category == .simulatorRuntime }.allSatisfy { !$0.canClean })
        let result = try await adapter.clean(CleanerCleanupRequest(snapshotID: snapshot.id, itemIDs: ["runtime:\(cleanerRuntimeImageID)"]))
        #expect(!result.failures.isEmpty)
        #expect(await recorder.deletionCommands.isEmpty)
    }
    @Test func malformedDeviceInventoryCannotAuthorizeRuntimeRemoval() async throws {
        let runtimeJSON = """
        {"\(cleanerRuntimeImageID)":{"identifier":"\(cleanerRuntimeImageID)","runtimeIdentifier":"\(cleanerRuntimeIdentifier)","deletable":true,"sizeBytes":4096}}
        """
        let malformed = """
        {"devices":{"\(cleanerRuntimeIdentifier)":[{"udid":"invalid","name":"Phone","state":"Booted"}]},"runtimes":[]}
        """
        let recorder = CleanerCommandRecorder(deviceJSON: malformed, runtimeJSON: runtimeJSON)
        let adapter = XcodeCleanerSimulator(run: { try await recorder.run($0) })
        let snapshot = try await adapter.scan()
        let runtime = try #require(snapshot.items.first { $0.category == .simulatorRuntime })
        #expect(!runtime.canClean)
        _ = try await adapter.clean(.init(snapshotID: snapshot.id, itemIDs: [runtime.id]))
        #expect(await recorder.deletionCommands.isEmpty)
    }
}

private actor CleanerCancelAfterDelete {
    let secondID: String
    var deletions: [[String]] = []
    init(secondID: String) { self.secondID = secondID }
    func run(_ command: CleanerCommand) -> CleanerCommandResult {
        if command.arguments == ["simctl", "list", "--json"] {
            let json = """
            {"devices":{"\(cleanerRuntimeIdentifier)":[{"udid":"\(cleanerDeviceID)","name":"First","state":"Shutdown"},{"udid":"\(secondID)","name":"Second","state":"Shutdown"}]},"runtimes":[]}
            """
            return .init(exitCode: 0, stdout: json, stderr: "")
        }
        if command.arguments == ["simctl", "runtime", "list", "--json"] { return .init(exitCode: 0, stdout: "{}", stderr: "") }
        deletions.append(command.arguments)
        withUnsafeCurrentTask { $0?.cancel() }
        return .init(exitCode: 0, stdout: "", stderr: "")
    }
}
#endif
