#if os(macOS)
import AppKit
import Foundation

/// The single live dependency instance shares this gate across Settings and all
/// switch providers. Actor reentrancy is bounded by explicit mutation ownership.
actor TailscaleCoordinator {
    typealias Runner = @Sendable (URL, [String], Duration, @escaping @Sendable (String) -> Void) async throws -> TailscaleCommandResult
    private let candidates: [URL]
    private let exists: @Sendable (URL) -> Bool
    private let run: Runner
    private let openAuthorization: @MainActor @Sendable (URL) -> Void
    private var executable: URL?
    private var mutationInFlight = false
    private var revision = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(candidates: [URL] = [
        URL(fileURLWithPath: "/Applications/Tailscale.app/Contents/MacOS/Tailscale"),
        URL(fileURLWithPath: "/Applications/Tailscale.app/Contents/MacOS/tailscale"),
        URL(fileURLWithPath: "/usr/local/bin/tailscale"),
        URL(fileURLWithPath: "/opt/homebrew/bin/tailscale")
    ], exists: @escaping @Sendable (URL) -> Bool = TailscaleExecutablePolicy.isDirectExecutable, run: @escaping Runner = { try await TailscaleCommandRunner.run(executable: $0, arguments: $1, timeout: $2, onOutput: $3) }, openAuthorization: @escaping @MainActor @Sendable (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.candidates = candidates; self.exists = exists; self.run = run; self.openAuthorization = openAuthorization
    }

    func snapshot() async throws -> TailscaleSnapshot {
        guard !mutationInFlight else { throw TailscaleError.busy }
        let ticket = revision
        let path = try await resolveExecutable()
        let accounts = try await readAccounts(path)
        let connection = try await readConnection(path)
        var preferences: [TailscalePreference: Bool] = [:]
        do { preferences = try await readPreferences(path) }
        catch is CancellationError { throw CancellationError() }
        catch { /* Older clients can still connect and manage accounts. */ }
        let finalAccounts = try await readAccounts(path)
        guard !mutationInFlight, ticket == revision,
              accounts.first(where: \.isActive)?.id == finalAccounts.first(where: \.isActive)?.id else { throw TailscaleError.busy }
        return .init(accounts: finalAccounts, connection: connection, preferences: preferences, preferencesAvailable: !preferences.isEmpty)
    }

    func perform(_ operation: TailscaleOperation) async throws {
        try Task.checkCancellation()
        guard !mutationInFlight else { throw TailscaleError.busy }
        mutationInFlight = true; revision += 1
        defer {
            mutationInFlight = false; revision += 1
            let waiters = idleWaiters; idleWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        let arguments = try TailscaleCLI.arguments(for: operation)
        let path = try await resolveExecutable()
        let before = try await readConnection(path)
        let profiles = try await readAccounts(path)
        if let expected = operation.expectedAccountID {
            guard profiles.first(where: \.isActive)?.id == expected else { throw TailscaleError.invalidAccount }
        }
        switch operation.baseOperation {
        case .connect:
            guard before.status == .running || before.status == .stopped else { throw TailscaleError.authenticationRequired }
        case .renew, .logout:
            guard profiles.contains(where: \.isActive) else { throw TailscaleError.authenticationRequired }
        case .switchAccount(let id):
            guard profiles.contains(where: { $0.id == id }) else { throw TailscaleError.invalidAccount }
        case .setPreference(let preference, _):
            guard !before.requiresAuthentication else { throw TailscaleError.authenticationRequired }
            let values = try await readPreferences(path)
            guard values[preference] != nil else { throw TailscaleError.unsupported }
        case .disconnect, .login: break
        case .forAccount: preconditionFailure("baseOperation unwraps account scope")
        }
        if let expected = operation.expectedAccountID {
            guard try await readAccounts(path).first(where: \.isActive)?.id == expected else { throw TailscaleError.invalidAccount }
        }
        try Task.checkCancellation()
        let result: TailscaleCommandResult
        if operation.isAuthorization {
            result = try await authorize(path: path, arguments: arguments)
        } else {
            result = try await run(path, arguments, .seconds(30), { _ in })
        }
        guard result.exitCode == 0 else {
            if let state = try? await readConnection(path), state.requiresAuthentication { throw TailscaleError.authenticationRequired }
            throw TailscaleError.commandFailed
        }
        let after = try await readConnection(path)
        switch operation.baseOperation {
        case .connect:
            guard after.status == .running else { throw after.requiresAuthentication ? TailscaleError.authenticationRequired : .commandFailed }
        case .disconnect:
            guard after.status == .stopped else { throw TailscaleError.commandFailed }
        case .login, .renew:
            guard after.status == .running else { throw TailscaleError.authenticationRequired }
        case .switchAccount(let id):
            guard try await readAccounts(path).first(where: \.isActive)?.id == id else { throw TailscaleError.commandFailed }
        case .setPreference(let preference, let value):
            guard try await readAccounts(path).first(where: \.isActive)?.id == profiles.first(where: \.isActive)?.id,
                  try await readPreferences(path)[preference] == value else { throw TailscaleError.commandFailed }
        case .logout:
            guard after.status != .running else { throw TailscaleError.commandFailed }
        case .forAccount: preconditionFailure("baseOperation unwraps account scope")
        }
    }

    func waitForIdle() async {
        guard mutationInFlight else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func resolveExecutable() async throws -> URL {
        if let executable { return executable }
        let installed = candidates.filter(exists)
        guard !installed.isEmpty else {
            if candidates.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) { throw TailscaleError.unavailable }
            throw TailscaleError.notInstalled
        }
        for path in installed {
            do {
                _ = try await readConnection(path)
                // Discovery is read-only. Once pinned, mutations never retry on a
                // different client/daemon, even if the selected client fails.
                if executable == nil { executable = path }
                return executable ?? path
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        throw TailscaleError.unavailable
    }
    private func readConnection(_ path: URL) async throws -> TailscaleConnection {
        let result = try await run(path, ["status", "--json", "--peers=false"], .seconds(15), { _ in })
        guard result.exitCode == 0 else { throw TailscaleError.unavailable }
        return try TailscaleCLI.decodeStatus(Data(result.stdout.utf8))
    }
    private func readAccounts(_ path: URL) async throws -> [TailscaleAccount] {
        let result = try await run(path, ["switch", "--list", "--json"], .seconds(15), { _ in })
        guard result.exitCode == 0 else { throw TailscaleError.unsupported }
        return try TailscaleCLI.decodeAccounts(Data(result.stdout.utf8))
    }
    private func readPreferences(_ path: URL) async throws -> [TailscalePreference: Bool] {
        let result = try await run(path, ["get", "--json"], .seconds(15), { _ in })
        guard result.exitCode == 0 else { throw TailscaleError.unsupported }
        return try TailscaleCLI.decodePreferences(Data(result.stdout.utf8))
    }
    private func authorize(path: URL, arguments: [String]) async throws -> TailscaleCommandResult {
        let (stream, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(128))
        defer { continuation.finish() }
        let runner = run, opener = openAuthorization
        return try await withThrowingTaskGroup(of: TailscaleCommandResult?.self) { group in
            group.addTask {
                defer { continuation.finish() }
                return try await runner(path, arguments, .seconds(180), { continuation.yield($0) })
            }
            group.addTask {
                var pending = "", opened: Set<URL> = []
                for await chunk in stream {
                    pending += chunk
                    // Wait for a line boundary, since a token may span pipe reads.
                    while let newline = pending.firstIndex(of: "\n") {
                        let line = String(pending[...newline])
                        pending.removeSubrange(...newline)
                        if let url = TailscaleCLI.authorizationURL(in: line), opened.insert(url).inserted {
                            try Task.checkCancellation()
                            await opener(url)
                        }
                    }
                    if pending.utf8.count > 8192 { pending = String(pending.suffix(4096)) }
                }
                return nil
            }
            var result: TailscaleCommandResult?
            do {
                for try await item in group { if let item { result = item } }
            } catch { group.cancelAll(); throw error }
            try Task.checkCancellation()
            guard let result else { throw TailscaleError.commandFailed }
            return result
        }
    }
}

/// Official CLI launchers can be shell wrappers without `exec`, leaving an
/// unowned login child alive after cancelling the wrapper. Run the direct app
/// binary (both bundle spelling variants) or a native Homebrew binary instead.
enum TailscaleExecutablePolicy {
    static func isDirectExecutable(_ url: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 4), prefix.count == 4 else { return false }
        let magic = Array(prefix)
        return [
            [0xfe, 0xed, 0xfa, 0xce], [0xce, 0xfa, 0xed, 0xfe],
            [0xfe, 0xed, 0xfa, 0xcf], [0xcf, 0xfa, 0xed, 0xfe],
            [0xca, 0xfe, 0xba, 0xbe], [0xbe, 0xba, 0xfe, 0xca],
            [0xca, 0xfe, 0xba, 0xbf], [0xbf, 0xba, 0xfe, 0xca]
        ].contains(magic.map(Int.init))
    }
}
#endif
