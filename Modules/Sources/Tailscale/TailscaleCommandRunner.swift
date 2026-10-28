#if os(macOS)
import Darwin
import Foundation

public struct TailscaleCommandResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public init(exitCode: Int32, stdout: String = "", stderr: String = "") { self.exitCode = exitCode; self.stdout = stdout; self.stderr = stderr }
}

/// All process accesses and terminal reasons share one lock. Pipe reads run on
/// blocking Dispatch workers, with bounded buffers; no work blocks the main actor.
private final class TailscaleOwnedProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var reason: (any Error)?
    private var bytes = 0
    private var finishedPipes = 0
    private var ownedGroup: pid_t?
    func launch(executable: URL, arguments: [String], stdout: Pipe, stderr: Pipe) throws {
        try lock.withLock {
            if let reason { throw reason }
            process.executableURL = executable; process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdout; process.standardError = stderr
            try process.run()
            let pid = process.processIdentifier
            // Foundation normally creates a child process group. Validate it
            // explicitly; never signal a group inherited from OnlySwitch.
            if getpgid(pid) == pid { ownedGroup = pid }
        }
    }
    var running: Bool { lock.withLock { process.isRunning } }
    var status: Int32 { lock.withLock { process.terminationStatus } }
    var failure: (any Error)? { lock.withLock { reason } }
    var pipesFinished: Bool { lock.withLock { finishedPipes == 2 } }
    func pipeFinished() { lock.withLock { finishedPipes += 1 } }
    private func killOwnedProcesses() {
        if let ownedGroup { kill(-ownedGroup, SIGKILL) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    func stop(_ error: any Error) {
        lock.withLock {
            guard reason == nil else { return }
            reason = error
            killOwnedProcesses()
        }
    }
    func accept(_ count: Int) -> Bool {
        lock.withLock {
            bytes += count
            guard bytes <= 1_048_576 else {
                if reason == nil { reason = TailscaleError.outputLimit }
                killOwnedProcesses()
                return false
            }
            return true
        }
    }
}

public enum TailscaleCommandRunner {
    @concurrent public static func run(executable: URL, arguments: [String], timeout: Duration, onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws -> TailscaleCommandResult {
        let owned = TailscaleOwnedProcess(), output = Pipe(), errorPipe = Pipe()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            do { try owned.launch(executable: executable, arguments: arguments, stdout: output, stderr: errorPipe) }
            catch {
                try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
                try? errorPipe.fileHandleForReading.close(); try? errorPipe.fileHandleForWriting.close()
                if error is CancellationError { throw error }
                throw TailscaleError.unavailable
            }
            // Foundation has duplicated the write ends into the child.
            try? output.fileHandleForWriting.close(); try? errorPipe.fileHandleForWriting.close()
            async let stdout = drain(output.fileHandleForReading, owned: owned, onOutput: onOutput)
            async let stderr = drain(errorPipe.fileHandleForReading, owned: owned, onOutput: onOutput)
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while owned.running || !owned.pipesFinished {
                if ContinuousClock.now >= deadline { owned.stop(TailscaleError.timedOut) }
                do { try await Task.sleep(for: .milliseconds(15)) }
                catch {
                    owned.stop(CancellationError())
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global(qos: .utility).async {
                            while owned.running { Thread.sleep(forTimeInterval: 0.005) }
                            continuation.resume()
                        }
                    }
                }
            }
            let captured = await (stdout, stderr)
            try Task.checkCancellation()
            if let failure = owned.failure { throw failure }
            return .init(exitCode: owned.status, stdout: captured.0, stderr: captured.1)
        } onCancel: { owned.stop(CancellationError()) }
    }

    private static func drain(_ handle: FileHandle, owned: TailscaleOwnedProcess, onOutput: @escaping @Sendable (String) -> Void) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                defer { try? handle.close(); owned.pipeFinished() }
                var data = Data()
                let descriptor = handle.fileDescriptor
                let flags = fcntl(descriptor, F_GETFL)
                guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                    owned.stop(TailscaleError.commandFailed)
                    continuation.resume(returning: "")
                    return
                }
                do {
                    while true {
                        if owned.failure != nil { break }
                        // POSIX read returns as soon as bytes arrive; Foundation's
                        // read(upToCount:) can wait to fill its buffer until EOF.
                        var buffer = [UInt8](repeating: 0, count: 8192)
                        let count = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
                        if count == 0 { break }
                        if count < 0 {
                            if errno == EINTR { continue }
                            if errno == EAGAIN || errno == EWOULDBLOCK {
                                var event = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
                                _ = poll(&event, 1, 25)
                                continue
                            }
                            throw TailscaleError.commandFailed
                        }
                        let chunk = Data(buffer.prefix(count))
                        if owned.accept(chunk.count) {
                            data.append(chunk)
                            onOutput(String(decoding: chunk, as: UTF8.self))
                        }
                    }
                } catch { owned.stop(TailscaleError.commandFailed) }
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }
}
#endif
