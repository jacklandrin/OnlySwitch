//
//  LowPowerModeSwitchTests.swift
//  OnlySwitchTests
//

import Synchronization
import Switches
import Testing
@testable import OnlySwitch

struct LowPowerModeSwitchTests {
    private struct Invocation: Equatable, Sendable {
        let operation: PrivilegedOperation
        let enabled: Bool
    }

    @Test(arguments: [true, false])
    @MainActor
    func changingStateUsesOnlyTheTypedLowPowerOperation(enabled: Bool) async throws {
        let invocations = Mutex<[Invocation]>([])
        let client = PrivilegedOperationClient(
            status: { .enabled },
            installFromInteractiveUI: {},
            removeFromInteractiveUI: {},
            perform: { operation, enabled in
                invocations.withLock { $0.append(.init(operation: operation, enabled: enabled)) }
            },
            openSystemSettings: {}
        )
        let sut = LowPowerModeSwitch(client: client)

        try await sut.operateSwitch(isOn: enabled)

        #expect(invocations.withLock { $0 } == [.init(operation: .lowPowerMode, enabled: enabled)])
    }

    @Test
    @MainActor
    func statusUsesTheUnprivilegedStatusReader() async {
        let reads = Mutex(0)
        let sut = LowPowerModeSwitch(
            client: .init(),
            statusReader: {
                reads.withLock { $0 += 1 }
                return true
            }
        )

        let status = await sut.currentStatus()

        #expect(status == true)
        #expect(reads.withLock { $0 } == 1)
        #expect(LowpowerModeCMD.status == "pmset -g | grep lowpowermode")
    }

    @Test
    @MainActor
    func authorizationFailureIsPropagatedWithoutReportingSuccess() async {
        let client = PrivilegedOperationClient(
            status: { .notInstalled },
            installFromInteractiveUI: {},
            removeFromInteractiveUI: {},
            perform: { _, _ in throw PrivilegedOperationClientError.notInstalled },
            openSystemSettings: {}
        )
        let sut = LowPowerModeSwitch(client: client)

        await #expect(throws: PrivilegedOperationClientError.notInstalled) {
            try await sut.operateSwitch(isOn: true)
        }
    }
}
