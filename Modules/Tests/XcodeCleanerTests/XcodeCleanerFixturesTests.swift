#if os(macOS)
import Foundation
import Testing
@testable import XcodeCleaner

struct CleanerFixture {
    let home: URL
    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("OnlySwitchCleanerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
    func url(_ path: String) -> URL { home.appendingPathComponent(path) }
    @discardableResult func write(_ path: String, bytes: Int = 16) throws -> URL {
        let destination = url(path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 42, count: bytes).write(to: destination)
        return destination
    }
    func item(_ category: CleanerCategory, in snapshot: CleanerSnapshot) throws -> CleanerItem {
        try #require(snapshot.items.first { $0.category == category })
    }
    func request(_ item: CleanerItem, in snapshot: CleanerSnapshot) -> CleanerCleanupRequest {
        CleanerCleanupRequest(snapshotID: snapshot.id, itemIDs: [item.id])
    }
}

actor CleanerCommandRecorder {
    var commands: [CleanerCommand] = []
    var deviceJSON: String
    var runtimeJSON: String
    var failInventory = false
    init(deviceJSON: String, runtimeJSON: String = "{}") {
        self.deviceJSON = deviceJSON
        self.runtimeJSON = runtimeJSON
    }
    func replaceDevices(_ json: String) { deviceJSON = json }
    func setInventoryFailure() { failInventory = true }
    func run(_ command: CleanerCommand) async throws -> CleanerCommandResult {
        commands.append(command)
        if command.arguments == ["simctl", "list", "--json"] {
            return CleanerCommandResult(exitCode: failInventory ? 1 : 0, stdout: deviceJSON, stderr: failInventory ? "service unavailable" : "")
        }
        if command.arguments == ["simctl", "runtime", "list", "--json"] {
            return CleanerCommandResult(exitCode: 0, stdout: runtimeJSON, stderr: "")
        }
        return CleanerCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    var deletionCommands: [CleanerCommand] { commands.filter { $0.arguments.contains("delete") } }
}

let cleanerDeviceID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
let cleanerRuntimeImageID = "11111111-2222-3333-4444-555555555555"
let cleanerRuntimeIdentifier = "com.apple.CoreSimulator.SimRuntime.iOS-27-1"
func cleanerDevices(state: String = "Shutdown", available: Bool = true) -> String {
    """
    {"devices":{"\(cleanerRuntimeIdentifier)":[{"udid":"\(cleanerDeviceID)","name":"Test iPhone","state":"\(state)","isAvailable":\(available)}]},"runtimes":[{"identifier":"\(cleanerRuntimeIdentifier)","name":"iOS 27.1","isAvailable":true}]}
    """
}
#endif
