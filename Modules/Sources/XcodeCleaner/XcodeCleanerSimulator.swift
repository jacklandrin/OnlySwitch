#if os(macOS)
import Foundation
import Synchronization
import Darwin

public struct CleanerCommand: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    public init(executable: URL = URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: [String]) { self.executable = executable; self.arguments = arguments }
}
public struct CleanerCommandResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public init(exitCode: Int32, stdout: String, stderr: String) { self.exitCode = exitCode; self.stdout = stdout; self.stderr = stderr }
}
private final class CleanerProcess: @unchecked Sendable {
    // Every process access, including cancellation, is serialized by this lock.
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    func launch(_ command: CleanerCommand, output: Pipe, error: Pipe) throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        process.executableURL = command.executable; process.arguments = command.arguments
        process.standardOutput = output; process.standardError = error
        try process.run()
    }
    var running: Bool { lock.withLock { process.isRunning } }
    var status: Int32 { lock.withLock { process.terminationStatus } }
    func cancel() { lock.withLock { cancelled = true; if process.isRunning { kill(process.processIdentifier, SIGKILL) } } }
}
public enum CleanerCommandRunner {
    @concurrent public static func run(_ command: CleanerCommand) async throws -> CleanerCommandResult {
        let process = CleanerProcess(), output = Pipe(), error = Pipe()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try process.launch(command, output: output, error: error)
            async let stdout = drain(output.fileHandleForReading)
            async let stderr = drain(error.fileHandleForReading)
            let deadline = ContinuousClock.now.advanced(by: .seconds(60))
            while process.running {
                if ContinuousClock.now > deadline { process.cancel() }
                do { try await Task.sleep(for: .milliseconds(40)) }
                catch {
                    process.cancel()
                    // Cancellation must still wait for Foundation to observe process exit.
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global(qos: .utility).async {
                            while process.running { Thread.sleep(forTimeInterval: 0.01) }
                            continuation.resume()
                        }
                    }
                    break
                }
            }
            let result = await CleanerCommandResult(exitCode: process.status, stdout: stdout, stderr: stderr)
            try Task.checkCancellation()
            return result
        } onCancel: { process.cancel() }
    }
    private static func drain(_ handle: FileHandle) async -> String {
        await withCheckedContinuation { continuation in
            // Blocking pipe reads belong on a Dispatch worker, never the cooperative executor.
            DispatchQueue.global(qos: .utility).async {
                var stored = Data()
                while let chunk = try? handle.read(upToCount: 8192), !chunk.isEmpty {
                    if stored.count < 1_048_576 { stored.append(chunk.prefix(1_048_576 - stored.count)) }
                }
                try? handle.close()
                continuation.resume(returning: String(decoding: stored, as: UTF8.self))
            }
        }
    }
}
public actor XcodeCleanerSimulator {
    private let run: @Sendable (CleanerCommand) async throws -> CleanerCommandResult
    private let home: URL?
    private let measureDevice: @Sendable (URL) throws -> Int64
    private var contexts = CleanerSnapshotContexts<[String: Target]>()
    private var sequence = 0
    private struct Target: Equatable, Sendable { var identifier: String; var runtime: String; var booted: Bool; var deletable: Bool; var fingerprint: String }
    private struct Inventory: Decodable {
        var devices: [String: [Device]]
        var runtimes: [Descriptor]?
    }
    private struct Device: Decodable { var udid: String; var name: String; var state: String; var isAvailable: Bool? }
    private struct Descriptor: Decodable { var identifier: String; var name: String }
    private struct Runtime: Decodable { var identifier: String; var runtimeIdentifier: String?; var runtimeBundlePath: String?; var deletable: Bool?; var sizeBytes: Int64?; var state: String? }
    public init(home: URL? = nil, measureDevice: (@Sendable (URL) throws -> Int64)? = nil, run: @escaping @Sendable (CleanerCommand) async throws -> CleanerCommandResult = CleanerCommandRunner.run) {
        self.home = home; self.run = run; self.measureDevice = measureDevice ?? { try XcodeCleanerFileSystem.measure($0) }
    }
    public func scan() async throws -> CleanerSnapshot {
        sequence += 1
        let ticket = sequence
        let (snapshot, targets) = try await Self.inventory(home: home, run: run, measureDevice: measureDevice, measureSizes: true)
        try Task.checkCancellation()
        contexts.insert(targets, id: snapshot.id, sequence: ticket)
        return snapshot
    }
    public func activateSnapshot(_ id: UUID) { _ = contexts.activate(id) }
    @concurrent private static func inventory(home: URL?, run: @Sendable (CleanerCommand) async throws -> CleanerCommandResult, measureDevice: @Sendable (URL) throws -> Int64, measureSizes: Bool) async throws -> (CleanerSnapshot, [String: Target]) {
        var snapshot = CleanerSnapshot(), targets: [String: Target] = [:]
        var devices: Inventory?
        do {
            let result = try await run(.init(arguments: ["simctl", "list", "--json"]))
            guard result.exitCode == 0 else { throw CleanerFailure(key: "Xcode Cleaner Simulator Unavailable", detail: result.stderr) }
            devices = try JSONDecoder().decode(Inventory.self, from: Data(result.stdout.utf8))
            for (runtime, entries) in devices!.devices {
                for device in entries {
                    try Task.checkCancellation()
                    guard UUID(uuidString: device.udid) != nil else { throw CleanerFailure(key: "Xcode Cleaner Simulator Unavailable") }
                    let id = "device:" + device.udid
                    guard targets[id] == nil else { throw CleanerFailure(key: "Xcode Cleaner Simulator Unavailable") }
                    let booted = device.state != "Shutdown"
                    var bytes: Int64?
                    if measureSizes, let home {
                        let root = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/" + device.udid)
                        if root.resolvingSymlinksInPath().path == root.standardizedFileURL.path { bytes = try? measureDevice(root) }
                    }
                    let runtimeName = devices?.runtimes?.first { $0.identifier == runtime }?.name
                    snapshot.items.append(.init(id: id, category: .simulatorDevice, title: device.name, bytes: bytes, canClean: !booted, requiresConfirmation: true, detail: runtime, statusKey: booted ? "Xcode Cleaner Device Running" : (device.isAvailable == false ? "Unavailable" : nil), runtimeIdentifier: runtime, runtimeName: runtimeName))
                    targets[id] = Target(identifier: device.udid, runtime: runtime, booted: booted, deletable: !booted, fingerprint: device.name + runtime)
                }
            }
        } catch is CancellationError { throw CancellationError() }
        catch { devices = nil; snapshot.items.removeAll(); targets.removeAll(); snapshot.failures.append(.init(key: "Xcode Cleaner Simulator Unavailable", detail: error.localizedDescription)) }
        do {
            let result = try await run(.init(arguments: ["simctl", "runtime", "list", "--json"]))
            guard result.exitCode == 0 else { throw CleanerFailure(key: "Xcode Cleaner Simulator Unavailable", detail: result.stderr) }
            let runtimes = try JSONDecoder().decode([String: Runtime].self, from: Data(result.stdout.utf8))
            for (key, runtime) in runtimes {
                guard UUID(uuidString: key) != nil, key == runtime.identifier, let runtimeID = runtime.runtimeIdentifier else { throw CleanerFailure(key: "Xcode Cleaner Simulator Unavailable") }
                let used = targets.values.contains { $0.runtime == runtimeID && $0.booted }
                let removable = runtime.deletable == true && !used && devices != nil
                let name = devices?.runtimes?.first { $0.identifier == runtimeID }?.name ?? runtimeID
                let id = "runtime:" + key
                snapshot.items.append(.init(id: id, category: .simulatorRuntime, title: name, bytes: runtime.sizeBytes, canClean: removable, requiresConfirmation: true, detail: runtime.runtimeBundlePath ?? runtimeID, statusKey: removable ? nil : "Xcode Cleaner Runtime Protected", runtimeIdentifier: runtimeID, runtimeName: name))
                targets[id] = Target(identifier: key, runtime: runtimeID, booted: used, deletable: removable, fingerprint: runtimeID + (runtime.runtimeBundlePath ?? ""))
            }
        } catch is CancellationError { throw CancellationError() }
        catch { snapshot.failures.append(.init(key: "Xcode Cleaner Simulator Unavailable", detail: error.localizedDescription)) }
        return (snapshot, targets)
    }
    public func clean(_ request: CleanerCleanupRequest) async throws -> CleanerCleanupResult {
        guard let oldTargets = contexts[request.snapshotID] else { return .init(failures: request.itemIDs.map { .init(key: "Xcode Cleaner Stale Scan", itemID: $0) }) }
        contexts.pin(request.snapshotID)
        defer { contexts.unpin(request.snapshotID) }
        let (_, freshTargets) = try await Self.inventory(home: home, run: run, measureDevice: measureDevice, measureSizes: false)
        var result = CleanerCleanupResult(), seen = Set<String>()
        let orderedIDs = request.itemIDs.filter { seen.insert($0).inserted }
        for (offset, id) in orderedIDs.enumerated() {
            if Task.isCancelled {
                result.failures += orderedIDs[offset...].map { .init(key: "Xcode Cleaner Remove Failed", itemID: $0) }
                return result
            }
            guard let old = oldTargets[id], let fresh = freshTargets[id], old.identifier == fresh.identifier, old.runtime == fresh.runtime, old.fingerprint == fresh.fingerprint, fresh.deletable, !fresh.booted else {
                result.failures.append(.init(key: "Xcode Cleaner Stale Scan", itemID: id)); continue
            }
            let arguments = id.hasPrefix("device:") ? ["simctl", "delete", fresh.identifier] : ["simctl", "runtime", "delete", fresh.identifier]
            do {
                let command = try await run(.init(arguments: arguments))
                if command.exitCode == 0 { result.cleanedIDs.append(id) }
                else { result.failures.append(.init(key: "Xcode Cleaner Remove Failed", detail: command.stderr, itemID: id)) }
            } catch is CancellationError {
                result.failures += orderedIDs[offset...].map { .init(key: "Xcode Cleaner Remove Failed", itemID: $0, mayHaveRemovedContents: $0 == id) }
                return result
            }
            catch { result.failures.append(CleanerFailure.wrapping(error).scoped(to: id)) }
        }
        return result
    }
}
#endif
