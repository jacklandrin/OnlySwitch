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
