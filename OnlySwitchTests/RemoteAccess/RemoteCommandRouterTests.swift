import RemoteCore
import Switches
import XCTest
@testable import OnlySwitch

@MainActor
final class RemoteCommandRouterTests: XCTestCase {
    func testDuplicateRequestExecutesOnlyOnce() async {
        let control = FakeSwitch(type: .darkMode, visible: true)
        let router = RemoteCommandRouter(resolveBuiltIn: { _ in control })
        let request = RemoteActionRequest(
            requestID: UUID(),
            controlID: .init(kind: .builtIn, value: "2"),
            action: .setState(true)
        )

        async let first = router.perform(request)
        async let second = router.perform(request)
        let results = await [first, second]

        XCTAssertEqual(control.operationCount, 1)
        XCTAssertEqual(results[0], results[1])
    }

    func testRejectsUnavailableControlBeforeExecution() async {
        let control = FakeSwitch(type: .airPods, visible: false)
        let router = RemoteCommandRouter(resolveBuiltIn: { _ in control })

        let result = await router.perform(.init(
            requestID: UUID(),
            controlID: .init(kind: .builtIn, value: "512"),
            action: .setState(true)
        ))

        XCTAssertEqual(result.error?.code, .controlUnavailable)
        XCTAssertEqual(control.operationCount, 0)
    }

    func testValidatesExactBuiltInIdentityAndActionCompatibility() async {
        let button = FakeSwitch(type: .emptyTrash, visible: true)
        let router = RemoteCommandRouter(resolveBuiltIn: { _ in button })

        let aliasedID = await router.perform(.init(
            requestID: UUID(),
            controlID: .init(kind: .builtIn, value: "016384"),
            action: .trigger
        ))
        let wrongAction = await router.perform(.init(
            requestID: UUID(),
            controlID: .init(kind: .builtIn, value: "16384"),
            action: .setState(true)
        ))

        XCTAssertEqual(aliasedID.error?.code, .controlNotFound)
        XCTAssertEqual(wrongAction.error?.code, .actionNotSupported)
        XCTAssertEqual(button.operationCount, 0)
    }

    func testRoutesShortcutAndEvolutionByExactIdentifier() async {
        var shortcutNames: [String] = []
        var evolutionActions: [RemoteControlAction] = []
        let evolutionID = UUID()
        let evolution = EvolutionItem(
            id: evolutionID,
            name: "Deploy",
            controlType: .Button,
            singleCommand: EvolutionCommand(commandType: .single, commandString: "deploy")
        )
        let router = RemoteCommandRouter(
            resolveBuiltIn: { _ in nil },
            installedShortcutNames: { ["Focus Setup"] },
            runShortcut: { shortcutNames.append($0) },
            resolveEvolution: { $0 == evolutionID ? evolution : nil },
            runEvolution: { _, action in evolutionActions.append(action) }
        )

        let shortcut = await router.perform(.init(
            requestID: UUID(),
            controlID: .init(kind: .shortcut, value: "Focus Setup"),
            action: .trigger
        ))
        let evolutionResult = await router.perform(.init(
            requestID: UUID(),
            controlID: .init(kind: .evolution, value: evolutionID.uuidString),
            action: .trigger
        ))

        XCTAssertNil(shortcut.error)
        XCTAssertNil(evolutionResult.error)
        XCTAssertEqual(shortcutNames, ["Focus Setup"])
        XCTAssertEqual(evolutionActions, [.trigger])
    }

    func testUninstalledShortcutIsRejectedWithoutInvokingRunner() async {
        var invocations: [String] = []
        let router = RemoteCommandRouter(
            resolveBuiltIn: { _ in nil },
            installedShortcutNames: { ["Installed"] },
            runShortcut: { invocations.append($0) }
        )

        let result = await router.perform(.init(
            requestID: UUID(),
            controlID: .init(kind: .shortcut, value: "Installed'; touch /tmp/pwned; '"),
            action: .trigger
        ))

        XCTAssertEqual(result.error?.code, .controlNotFound)
        XCTAssertTrue(invocations.isEmpty)
    }

    func testShortcutProcessPreservesHostileInstalledNameAsLiteralArgument() async throws {
        let recorder = ShortcutProcessRecorder()
        let client = RemoteShortcutProcessClient { executableURL, arguments in
            await recorder.record(executableURL: executableURL, arguments: arguments)
        }
        let name = "Deploy 'quoted'; $(touch /tmp/pwned) & done"

        try await client.runShortcut(named: name)

        let recordedInvocation = await recorder.invocation
        let invocation = try XCTUnwrap(recordedInvocation)
        XCTAssertEqual(invocation.executableURL.path, "/usr/bin/shortcuts")
        XCTAssertEqual(invocation.arguments, ["run", name])
    }

    func testSimultaneousDuplicateFailureExecutesOnceAndCachesFailure() async {
        let runner = SuspendedShortcutRunner(error: TestFailure())
        let router = RemoteCommandRouter(
            resolveBuiltIn: { _ in nil },
            installedShortcutNames: { ["Fail"] },
            runShortcut: { _ in try await runner.run() }
        )
        let request = RemoteActionRequest(
            requestID: UUID(),
            controlID: .init(kind: .shortcut, value: "Fail"),
            action: .trigger
        )

        let first = Task { await router.perform(request) }
        await runner.waitUntilStarted()
        let second = Task { await router.perform(request) }
        await Task.yield()
        runner.resume()
        let firstResult = await first.value
        let secondResult = await second.value
        let cachedResult = await router.perform(request)

        XCTAssertEqual(firstResult.error?.code, .executionFailed)
        XCTAssertEqual(secondResult, firstResult)
        XCTAssertEqual(cachedResult, firstResult)
        XCTAssertEqual(runner.operationCount, 1)
    }

    func testCancellingDuplicateWaiterDoesNotCancelSharedOperation() async {
        let runner = SuspendedShortcutRunner()
        let router = RemoteCommandRouter(
            resolveBuiltIn: { _ in nil },
            installedShortcutNames: { ["Slow"] },
            runShortcut: { _ in try await runner.run() }
        )
        let request = RemoteActionRequest(
            requestID: UUID(),
            controlID: .init(kind: .shortcut, value: "Slow"),
            action: .trigger
        )

        let first = Task { await router.perform(request) }
        await runner.waitUntilStarted()
        let cancelledWaiter = Task { await router.perform(request) }
        cancelledWaiter.cancel()
        await Task.yield()
        runner.resume()
        let firstResult = await first.value
        let cancelledWaiterResult = await cancelledWaiter.value
        let cachedResult = await router.perform(request)

        XCTAssertNil(firstResult.error)
        XCTAssertEqual(cancelledWaiterResult, firstResult)
        XCTAssertEqual(cachedResult, firstResult)
        XCTAssertEqual(runner.operationCount, 1)
    }

    func testRecentRequestCacheEvictsOldestResult() async {
        let cache = RecentRequestCache(capacity: 2)
        let ids = [UUID(), UUID(), UUID()]
        for id in ids {
            await cache.insert(.init(requestID: id, result: .success(nil)), for: id)
        }
        let first = await cache.result(for: ids[0])
        let second = await cache.result(for: ids[1])
        let third = await cache.result(for: ids[2])

        XCTAssertNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(third)
    }
}

private struct TestFailure: Error {}

private actor ShortcutProcessRecorder {
    struct Invocation: Sendable {
        let executableURL: URL
        let arguments: [String]
    }

    private(set) var invocation: Invocation?

    func record(executableURL: URL, arguments: [String]) {
        invocation = .init(executableURL: executableURL, arguments: arguments)
    }
}

@MainActor
private final class SuspendedShortcutRunner {
    private let error: (any Error)?
    private var operationContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var operationCount = 0

    init(error: (any Error)? = nil) {
        self.error = error
    }

    func run() async throws {
        operationCount += 1
        let continuations = startedContinuations
        startedContinuations.removeAll()
        continuations.forEach { $0.resume() }
        await withCheckedContinuation { operationContinuation = $0 }
        if let error { throw error }
    }

    func waitUntilStarted() async {
        guard operationCount == 0 else { return }
        await withCheckedContinuation { startedContinuations.append($0) }
    }

    func resume() {
        operationContinuation?.resume()
        operationContinuation = nil
    }
}
