//
//  AgentShellJob.swift
//  Modules
//

import Darwin
import Foundation

/// One `/bin/sh -c` process. `Process` is not `Sendable`, so access is
/// serialized by a lock. Terminating it also terminates every descendant
/// (e.g. `brew` → `ruby` → `curl`), not just the shell.
final class AgentShellJob: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var isCancelled = false

    init(shell: String, code: String, environment: [String: String]) {
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", code]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
    }

    func run() -> Result<String, Error> {
        let stdout = Pipe()
        let stderr = Pipe()
        lock.lock()
        process.standardOutput = stdout
        process.standardError = stderr
        if isCancelled {
            lock.unlock()
            return .failure(CancellationError())
        }
        do {
            try process.run()
        } catch {
            lock.unlock()
            return .failure(AgentScriptError(message: error.localizedDescription))
        }
        lock.unlock()

        // Drain both pipes concurrently so a chatty command cannot fill a pipe and block.
        let group = DispatchGroup()
        let errorData = AgentLockedValue(Data())
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorData.set(stderr.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        group.wait()

        lock.lock()
        let cancelled = isCancelled
        lock.unlock()
        if cancelled {
            return .failure(CancellationError())
        }

        let output = String(decoding: outputData, as: UTF8.self)
        let status = process.terminationStatus
        guard status == 0 else {
            let message = AgentScriptRunner.shellFailureMessage(
                stderr: String(decoding: errorData.get(), as: UTF8.self),
                stdout: output,
                status: status
            )
            return .failure(AgentScriptError(message: message))
        }
        return .success(AgentScriptRunner.normalizedOutput(output))
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        guard process.isRunning else { return }
        for pid in Self.descendants(of: process.processIdentifier).reversed() {
            kill(pid, SIGTERM)
        }
        process.terminate()
    }

    /// All descendant process IDs, parents before children.
    static func descendants(of root: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var queue: [pid_t] = [root]
        while !queue.isEmpty {
            let parent = queue.removeFirst()
            let size = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(parent), nil, 0)
            guard size > 0 else { continue }
            let capacity = Int(size) / MemoryLayout<pid_t>.stride + 16
            var buffer = [pid_t](repeating: 0, count: capacity)
            let bytes = buffer.withUnsafeMutableBytes {
                proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(parent), $0.baseAddress, Int32($0.count))
            }
            guard bytes > 0 else { continue }
            let children = buffer.prefix(Int(bytes) / MemoryLayout<pid_t>.stride).filter { $0 > 0 && $0 != parent }
            result.append(contentsOf: children)
            queue.append(contentsOf: children)
        }
        return result
    }
}

final class AgentLockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
