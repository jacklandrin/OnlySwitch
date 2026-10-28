#if os(macOS)
import Foundation
import Testing
@testable import Tailscale

private actor TailscaleTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var open = false
    func wait() async {
        guard !open else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { open = true; continuation?.resume(); continuation = nil }
}
private actor TailscaleFakeDaemon {
    var status = "Running"
    private(set) var calls: [(URL, [String])] = []
    func response(_ path: URL, _ arguments: [String], failWrite: Bool = false) -> TailscaleCommandResult {
        calls.append((path, arguments))
        if arguments == ["status", "--json", "--peers=false"] { return .init(exitCode: 0, stdout: "{\"BackendState\":\"\(status)\"}") }
        if arguments == ["switch", "--list", "--json"] { return .init(exitCode: 0, stdout: #"[{"id":"home","nickname":"Home","tailnet":"example","account":"a@example.com","selected":true}]"#) }
        if arguments == ["get", "--json"] { return .init(exitCode: 0, stdout: #"{"accept-dns":true}"#) }
        if failWrite { return .init(exitCode: 1, stderr: "private-output-not-for-UI") }
        if arguments == ["down"] { status = "Stopped" }
        if arguments == ["up"] || arguments == ["login"] { status = "Running" }
        return .init(exitCode: 0)
    }
    func requireLogin() { status = "NeedsLogin" }
}

@Suite(.timeLimit(.minutes(1)))
struct TailscaleCoordinatorTests {
    private let path = URL(fileURLWithPath: "/test/official-tailscale")

    @Test(arguments: [false, true], ["", "existing-exit-node"])
    func savingLocalNetworkPreferenceDoesNotRequireOrChangeExitNode(desired: Bool, exitNodeID: String) async throws {
        let daemon = TailscaleLANPreferenceDaemon(initialValue: !desired, exitNodeID: exitNodeID)
        let coordinator = TailscaleCoordinator(candidates: [path], exists: { _ in true }, run: { _, args, _, _ in
            await daemon.response(args)
        })
        do {
            try await coordinator.perform(.forAccount("home", .setPreference(.allowLANAccess, desired)))
        } catch {
            Issue.record("An available LAN preference must be saveable with or without an exit node: \(error)")
        }
        let calls = await daemon.calls
        let writes = calls.filter { $0 != ["status", "--json", "--peers=false"] && $0 != ["switch", "--list", "--json"] && $0 != ["get", "--json"] }
        #expect(writes == [["set", "--exit-node-allow-lan-access=\(desired)"]])
        #expect(!calls.contains { $0.first == "up" || $0.first == "down" || ($0.first == "switch" && $0 != ["switch", "--list", "--json"]) })
        #expect(!writes.flatMap { $0 }.contains { $0 == "--exit-node" || $0.hasPrefix("--exit-node=") })
        let snapshot = try await coordinator.snapshot()
        #expect(snapshot.preferences[.allowLANAccess] == desired)
        #expect(snapshot.connection.hasExitNode == !exitNodeID.isEmpty)
        #expect(snapshot.accounts.first(where: \.isActive)?.id == "home")
        #expect(daemon.exitNodeID == exitNodeID)
    }

    @Test func officialShellLauncherCannotBeSelectedAsAnOwnedCLI() async throws {
        let fixture = try TailscaleProcessFixture(script: #"/Applications/Tailscale.app/Contents/MacOS/tailscale "$@""#)
        defer { fixture.remove() }
        #expect(!TailscaleExecutablePolicy.isDirectExecutable(fixture.executable))
        #expect(TailscaleExecutablePolicy.isDirectExecutable(URL(fileURLWithPath: "/usr/bin/true")))
        let daemon = TailscaleFakeDaemon()
        let coordinator = TailscaleCoordinator(candidates: [fixture.executable], run: { path, args, _, _ in await daemon.response(path, args) })
        await #expect(throws: TailscaleError.unavailable) { try await coordinator.snapshot() }
        #expect(await daemon.calls.isEmpty)
    }

    @Test func overlappingMutationsAreRejectedAcrossSuspension() async throws {
        let daemon = TailscaleFakeDaemon(), gate = TailscaleTestGate()
        let (started, signal) = AsyncStream<Void>.makeStream()
        defer { signal.finish() }
        let coordinator = TailscaleCoordinator(candidates: [path], exists: { _ in true }, run: { path, args, _, _ in
            if args == ["down"] { signal.yield(); await gate.wait() }
            return await daemon.response(path, args)
        })
        let first = Task { try await coordinator.perform(.disconnect) }
        for await _ in started { break }
        await #expect(throws: TailscaleError.busy) { try await coordinator.perform(.connect) }
        await gate.release()
        try await first.value
        #expect(await daemon.calls.filter { $0.1 == ["down"] }.count == 1)
    }

    @Test func readStartedBeforeMutationCannotReturnAnOldSnapshot() async throws {
        let daemon = TailscaleFakeDaemon(), gate = TailscaleTestGate()
        let (started, signal) = AsyncStream<Void>.makeStream()
        defer { signal.finish() }
        let coordinator = TailscaleCoordinator(candidates: [path], exists: { _ in true }, run: { path, args, _, _ in
            if args == ["get", "--json"] { signal.yield(); await gate.wait() }
            return await daemon.response(path, args)
        })
        let read = Task { try await coordinator.snapshot() }
        for await _ in started { break }
        try await coordinator.perform(.disconnect)
        await gate.release()
        await #expect(throws: TailscaleError.busy) { try await read.value }
    }

    @Test func failedWriteNeverRetriesAgainstAnotherDaemon() async throws {
        let daemon = TailscaleFakeDaemon()
        let second = URL(fileURLWithPath: "/test/other-tailscale")
        let coordinator = TailscaleCoordinator(candidates: [path, second], exists: { _ in true }, run: { path, args, _, _ in
            await daemon.response(path, args, failWrite: true)
        })
        await #expect(throws: TailscaleError.commandFailed) { try await coordinator.perform(.disconnect) }
        let calls = await daemon.calls
        #expect(calls.contains { $0.1 == ["down"] })
        #expect(calls.allSatisfy { $0.0 == path })
    }

    @Test func aConnectionSwitchCannotInitiateAnUnattendedLogin() async throws {
        let daemon = TailscaleFakeDaemon()
        await daemon.requireLogin()
        let coordinator = TailscaleCoordinator(candidates: [path], exists: { _ in true }, run: { path, args, _, _ in await daemon.response(path, args) })
        await #expect(throws: TailscaleError.authenticationRequired) { try await coordinator.perform(.connect) }
        #expect(await daemon.calls.allSatisfy { $0.1 != ["up"] && $0.1 != ["login"] })
    }

    @Test(arguments: [TailscaleAccountOperation.connect, .disconnect, .logout, .renew, .setPreference(.acceptDNS, false)])
    func staleAccountIntentCannotMutateTheNewActiveAccount(intent: TailscaleAccountOperation) async throws {
        let daemon = TailscaleFakeDaemon()
        let coordinator = TailscaleCoordinator(candidates: [path], exists: { _ in true }, run: { path, args, _, _ in await daemon.response(path, args) })
        await #expect(throws: TailscaleError.invalidAccount) { try await coordinator.perform(.forAccount("previous-account", intent)) }
        #expect(await daemon.calls.allSatisfy { $0.1 == ["status", "--json", "--peers=false"] || $0.1 == ["switch", "--list", "--json"] })
    }

    @MainActor @Test func loginOpensItsStreamedURLOnceBeforeCompletion() async throws {
        let daemon = TailscaleFakeDaemon(), gate = TailscaleTestGate()
        let (opened, signal) = AsyncStream<URL>.makeStream()
        defer { signal.finish() }
        let coordinator = TailscaleCoordinator(candidates: [path], exists: { _ in true }, run: { path, args, _, output in
            if args == ["login"] {
                output("To authenticate, visit:\nhttps://login.tail")
                output("scale.com/a/test-token\nhttps://login.tailscale.com/a/test-token\n")
                await gate.wait()
            }
            return await daemon.response(path, args)
        }, openAuthorization: { signal.yield($0) })
        let login = Task { try await coordinator.perform(.login) }
        var urls: [URL] = []
        for await url in opened {
            urls.append(url)
            await gate.release()
            break
        }
        try await login.value
        signal.finish()
        for await url in opened { urls.append(url) }
        #expect(urls.map(\.absoluteString) == ["https://login.tailscale.com/a/test-token"])
    }
}

/// Only the LAN Boolean can change; exit-node and account selection are fixed.
private actor TailscaleLANPreferenceDaemon {
    private var value: Bool
    let exitNodeID: String
    private(set) var calls: [[String]] = []
    init(initialValue: Bool, exitNodeID: String) {
        value = initialValue
        self.exitNodeID = exitNodeID
    }
    func response(_ arguments: [String]) -> TailscaleCommandResult {
        calls.append(arguments)
        if arguments == ["status", "--json", "--peers=false"] {
            let exit = exitNodeID.isEmpty ? "" : ",\"ExitNodeStatus\":{\"ID\":\"\(exitNodeID)\"}"
            return .init(exitCode: 0, stdout: "{\"BackendState\":\"Running\"\(exit)}")
        }
        if arguments == ["switch", "--list", "--json"] {
            return .init(exitCode: 0, stdout: #"[{"id":"home","nickname":"Home","tailnet":"example","account":"a@example.com","selected":true}]"#)
        }
        if arguments == ["get", "--json"] {
            return .init(exitCode: 0, stdout: "{\"exit-node-allow-lan-access\":\(value),\"exit-node\":\"\(exitNodeID)\"}")
        }
        if arguments == ["set", "--exit-node-allow-lan-access=true"] { value = true; return .init(exitCode: 0) }
        if arguments == ["set", "--exit-node-allow-lan-access=false"] { value = false; return .init(exitCode: 0) }
        return .init(exitCode: 1)
    }
}
#endif
