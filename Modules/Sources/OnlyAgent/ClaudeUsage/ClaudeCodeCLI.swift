import Dependencies
import Foundation
#if os(macOS)
import Darwin
#endif

public enum ClaudeSignInFailure: Error, Equatable, Sendable {
    case cliNotFound, failed, timedOut
}

public enum ClaudeSignInPhase: Equatable, Sendable {
    case idle
    case starting
    case waitingForBrowser(URL?)
    case succeeded
    case failed(ClaudeSignInFailure)
}

/// Talks to the user's Claude Code CLI. OnlySwitch never runs its own OAuth flow and never rotates
/// Claude Code's refresh token: it asks Claude Code to sign in or renew its own session, then reads
/// the credential Claude Code stored.
enum ClaudeCodeCLI {
    static let loginArguments = ["auth", "login", "--claudeai"]
    static let renewArguments = ["auth", "status"]
    private static let successMarkers = ["successfully logged in", "login successful", "logged in successfully"]

    // MARK: Locating the CLI

    /// Menu bar apps inherit launchd's minimal PATH, so `claude` (and the `node` an npm install needs)
    /// is usually missing. Merge the login shell's PATH with Claude Code's well-known install locations.
    static func environment() async -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        let wellKnown = [
            "\(home)/.local/bin", "\(home)/.claude/local", "\(home)/.claude/bin",
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        var seen = Set<String>()
        let entries = (await LoginShellPath.shared.value(environment: environment))
            + (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + wellKnown
        environment["PATH"] = entries.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        return environment
    }

    static func locate(environment: [String: String]) -> URL? {
        (environment["PATH"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appending(path: "claude") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // MARK: Renewing an expired session

    /// Runs `claude auth status` so Claude Code can renew its own expired access token.
    /// Returns whether the CLI ran; the caller re-reads the credential to see if anything changed.
    static func renewSession() async -> Bool {
        let environment = await environment()
        guard let claude = locate(environment: environment) else { return false }
        return await run(claude, arguments: renewArguments, environment: environment, timeout: .seconds(20)) != nil
    }

    // MARK: Signing in

    /// Runs `claude auth login --claudeai` in a pseudo-terminal, presses Enter when Claude Code offers to
    /// open the browser, and returns once Claude Code reports a successful login.
    static func signIn(onWaitingForBrowser: @escaping @Sendable (URL?) async -> Void) async throws {
        #if os(macOS)
        let environment = await environment()
        guard let claude = locate(environment: environment) else { throw ClaudeSignInFailure.cliNotFound }
        var primary: Int32 = -1
        var secondary: Int32 = -1
        // A very wide terminal keeps the long authorization URL on one line.
        var size = winsize(ws_row: 50, ws_col: 1000, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primary, &secondary, nil, nil, &size) == 0 else { throw ClaudeSignInFailure.failed }
        defer { close(primary) }
        _ = fcntl(primary, F_SETFL, O_NONBLOCK)
        let secondaryHandle = FileHandle(fileDescriptor: secondary, closeOnDealloc: true)

        let process = Process()
        process.executableURL = claude
        process.arguments = loginArguments
        var processEnvironment = environment
        processEnvironment["TERM"] = "xterm-256color"
        process.environment = processEnvironment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = secondaryHandle
        process.standardOutput = secondaryHandle
        process.standardError = secondaryHandle
        do { try process.run() } catch { throw ClaudeSignInFailure.failed }
        try? secondaryHandle.close()
        defer { if process.isRunning { process.terminate() } }

        var transcript = ""
        var pressedEnter = false
        var reportedWaiting = false
        var reportedURL: URL?
        let capacity = 8192
        var buffer = [UInt8](repeating: 0, count: capacity)
        let deadline = Date().addingTimeInterval(300)
        func drain() {
            while true {
                let count = read(primary, &buffer, capacity)
                guard count > 0 else { return }
                transcript += String(decoding: buffer[0 ..< count], as: UTF8.self)
                if transcript.count > 65_536 { transcript = String(transcript.suffix(32_768)) }
            }
        }
        while true {
            try Task.checkCancellation()
            drain()
            let visible = stripTerminalEscapes(transcript).lowercased()
            if !pressedEnter && visible.contains("press enter") {
                _ = "\r".utf8CString.withUnsafeBufferPointer { write(primary, $0.baseAddress, 1) }
                pressedEnter = true
            }
            if reportedURL == nil, let url = authorizationURL(in: transcript) {
                reportedURL = url
                reportedWaiting = true
                await onWaitingForBrowser(url)
            } else if !reportedWaiting && pressedEnter {
                reportedWaiting = true
                await onWaitingForBrowser(nil)
            }
            if successMarkers.contains(where: visible.contains) { return }
            if !process.isRunning {
                drain()
                if process.terminationStatus == 0 || successMarkers.contains(where: stripTerminalEscapes(transcript).lowercased().contains) { return }
                throw ClaudeSignInFailure.failed
            }
            if Date() >= deadline { throw ClaudeSignInFailure.timedOut }
            try await Task.sleep(for: .milliseconds(150))
        }
        #else
        throw ClaudeSignInFailure.cliNotFound
        #endif
    }

    static func authorizationURL(in text: String) -> URL? {
        let pattern = #"https://[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            var candidate = String(text[range])
            while let last = candidate.last, ".,;:)]}>'\"".contains(last) { candidate.removeLast() }
            guard let url = URL(string: candidate), let host = url.host?.lowercased(),
                  host == "claude.ai" || host.hasSuffix(".claude.ai") || host == "claude.com" || host.hasSuffix(".claude.com") || host.hasSuffix(".anthropic.com"),
                  url.path.contains("oauth") || url.path.contains("authorize") else { continue }
            return url
        }
        return nil
    }

    static func stripTerminalEscapes(_ text: String) -> String {
        text.replacingOccurrences(of: #"\x{1B}\][^\x{07}\x{1B}]*(\x{07}|\x{1B}\\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\x{1B}\[[0-9;?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
    }

    // MARK: Process helper

    /// Runs a non-interactive command and returns its exit status and stdout, or nil if it could not
    /// start or exceeded the timeout.
    static func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration, captureOutput: Bool = false) async -> (status: Int32, output: String)? {
        let box = ProcessBox()
        let process = box.process
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let collected = LockedOutput()
        if captureOutput {
            let pipe = Pipe()
            process.standardOutput = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil } else { collected.append(data) }
            }
        } else {
            process.standardOutput = FileHandle.nullDevice
        }
        let status: Int32? = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Int32?, Never>) in
                let once = ResumeOnce(continuation)
                box.process.terminationHandler = { finished in once.resume(finished.terminationStatus) }
                do { try box.process.run() } catch { once.resume(nil); return }
                Task {
                    try? await Task.sleep(for: timeout)
                    if box.process.isRunning { box.process.terminate(); once.resume(nil) }
                }
            }
        } onCancel: {
            if box.process.isRunning { box.process.terminate() }
        }
        guard let status else { return nil }
        if captureOutput { try? await Task.sleep(for: .milliseconds(100)) }
        return (status, collected.string)
    }
}

/// The login shell's PATH, captured once per launch.
actor LoginShellPath {
    static let shared = LoginShellPath()
    private var cached: [String]?

    func value(environment: [String: String]) async -> [String] {
        if let cached { return cached }
        let shell = environment["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        let marker = "__ONLYSWITCH_PATH__"
        let result = await ClaudeCodeCLI.run(URL(fileURLWithPath: shell), arguments: ["-l", "-i", "-c", "printf '\(marker)%s\(marker)' \"$PATH\""],
                                             environment: environment, timeout: .seconds(5), captureOutput: true)
        var entries: [String] = []
        if let output = result?.output, let start = output.range(of: marker),
           let end = output.range(of: marker, options: .backwards), start.upperBound <= end.lowerBound {
            entries = output[start.upperBound ..< end.lowerBound].split(separator: ":").map(String.init)
        }
        cached = entries
        return entries
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process = Process()
}

private final class LockedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) { lock.withLock { if data.count < 262_144 { data.append(chunk) } } }
    var string: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int32?, Never>?
    init(_ continuation: CheckedContinuation<Int32?, Never>) { self.continuation = continuation }
    func resume(_ value: Int32?) {
        let pending = lock.withLock { () -> CheckedContinuation<Int32?, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}

// MARK: - Session renewal

/// Throttles `claude auth status` so an expired session does not spawn the CLI on every panel open.
actor ClaudeCodeSessionRenewal {
    static let shared = ClaudeCodeSessionRenewal(renew: { await ClaudeCodeCLI.renewSession() }, now: { Date() })
    private let renew: @Sendable () async -> Bool
    private let now: @Sendable () -> Date
    private var lastAttempt: Date?

    init(renew: @escaping @Sendable () async -> Bool, now: @escaping @Sendable () -> Date) {
        self.renew = renew; self.now = now
    }

    func renewIfAllowed() async -> Bool {
        if let lastAttempt, now().timeIntervalSince(lastAttempt) < 60 { return false }
        lastAttempt = now()
        return await renew()
    }
}

// MARK: - Sign-in session

/// Owns the running `claude auth login` process. It deliberately outlives the panel: the menu bar
/// popover closes while the user is in the browser, and closing it must not abort the sign-in.
actor ClaudeCodeSignInSession {
    static let shared = ClaudeCodeSignInSession(signIn: { try await ClaudeCodeCLI.signIn(onWaitingForBrowser: $0) })
    private let signIn: @Sendable (@escaping @Sendable (URL?) async -> Void) async throws -> Void
    private var phase: ClaudeSignInPhase = .idle
    private var task: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<ClaudeSignInPhase>.Continuation] = [:]

    init(signIn: @escaping @Sendable (@escaping @Sendable (URL?) async -> Void) async throws -> Void) {
        self.signIn = signIn
    }

    func start() {
        guard task == nil else { return }
        update(.starting)
        let signIn = self.signIn
        task = Task {
            let result: ClaudeSignInPhase
            do {
                try await signIn { url in await self.browserReady(url) }
                result = .succeeded
            } catch is CancellationError { result = .idle }
            catch let failure as ClaudeSignInFailure { result = .failed(failure) }
            catch { result = .failed(.failed) }
            self.finish(result)
        }
    }

    func cancel() { task?.cancel() }

    /// Clears a finished result once a panel has acted on it, so it is not handled twice.
    func acknowledge() {
        if task == nil { phase = .idle }
    }

    func observe() -> AsyncStream<ClaudeSignInPhase> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ClaudeSignInPhase.self, bufferingPolicy: .bufferingNewest(8))
        observers[id] = continuation
        continuation.onTermination = { _ in Task { await self.removeObserver(id) } }
        continuation.yield(phase)
        return stream
    }

    private func browserReady(_ url: URL?) {
        guard task != nil else { return }
        update(.waitingForBrowser(url))
    }

    private func finish(_ result: ClaudeSignInPhase) {
        task = nil
        update(result)
    }

    private func update(_ newPhase: ClaudeSignInPhase) {
        phase = newPhase
        for continuation in observers.values { continuation.yield(newPhase) }
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }
}

public struct ClaudeCodeSignInClient: Sendable {
    public var start: @Sendable () async -> Void
    public var cancel: @Sendable () async -> Void
    public var acknowledge: @Sendable () async -> Void
    public var observe: @Sendable () async -> AsyncStream<ClaudeSignInPhase>
    public init(start: @escaping @Sendable () async -> Void, cancel: @escaping @Sendable () async -> Void,
                acknowledge: @escaping @Sendable () async -> Void, observe: @escaping @Sendable () async -> AsyncStream<ClaudeSignInPhase>) {
        self.start = start; self.cancel = cancel; self.acknowledge = acknowledge; self.observe = observe
    }
}

extension ClaudeCodeSignInClient: DependencyKey {
    public static let liveValue = Self(
        start: { await ClaudeCodeSignInSession.shared.start() },
        cancel: { await ClaudeCodeSignInSession.shared.cancel() },
        acknowledge: { await ClaudeCodeSignInSession.shared.acknowledge() },
        observe: { await ClaudeCodeSignInSession.shared.observe() })
    public static let testValue = Self(start: {}, cancel: {}, acknowledge: {}, observe: { AsyncStream { $0.finish() } })
}

public extension DependencyValues {
    var claudeCodeSignIn: ClaudeCodeSignInClient {
        get { self[ClaudeCodeSignInClient.self] }
        set { self[ClaudeCodeSignInClient.self] = newValue }
    }
}
