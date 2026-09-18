//
//  PrivilegedOperationClientTests.swift
//  OnlySwitchTests
//

import Dependencies
import Synchronization
import Testing
@testable import OnlySwitch

struct PrivilegedOperationClientTests {
    @Test(arguments: [
        (PrivilegedHelperServiceStatus.notRegistered, PrivilegedHelperStatus.notInstalled),
        (PrivilegedHelperServiceStatus.enabled, PrivilegedHelperStatus.enabled),
        (PrivilegedHelperServiceStatus.requiresApproval, PrivilegedHelperStatus.requiresApproval),
        (PrivilegedHelperServiceStatus.notFound, PrivilegedHelperStatus.unavailable),
        (PrivilegedHelperServiceStatus.unknown, PrivilegedHelperStatus.unavailable)
    ])
    func statusMapping(
        serviceStatus: PrivilegedHelperServiceStatus,
        expectedStatus: PrivilegedHelperStatus
    ) {
        #expect(PrivilegedHelperStatus(serviceStatus: serviceStatus) == expectedStatus)
    }

    @Test
    func performDoesNotRegisterHelperAsASideEffect() async {
        let registrations = Mutex(0)
        let client = PrivilegedOperationClient(
            status: { .notInstalled },
            installFromInteractiveUI: { registrations.withLock { $0 += 1 } },
            removeFromInteractiveUI: {},
            perform: { _, _ in throw PrivilegedOperationClientError.notInstalled },
            openSystemSettings: {}
        )

        await #expect(throws: PrivilegedOperationClientError.notInstalled) {
            try await client.perform(.lowPowerMode, true)
        }
        #expect(registrations.withLock { $0 } == 0)
    }

    @Test(arguments: [
        PrivilegedOperationClientError.connectionInterrupted,
        .connectionInvalidated,
        .helperRejected,
        .operationFailed
    ])
    func performPropagatesTypedXPCAndHelperFailures(error: PrivilegedOperationClientError) async {
        let client = PrivilegedOperationClient(
            status: { .enabled },
            installFromInteractiveUI: {},
            removeFromInteractiveUI: {},
            perform: { _, _ in throw error },
            openSystemSettings: {}
        )

        await #expect(throws: error) {
            try await client.perform(.clamshellSleepDisabled, false)
        }
    }
}
