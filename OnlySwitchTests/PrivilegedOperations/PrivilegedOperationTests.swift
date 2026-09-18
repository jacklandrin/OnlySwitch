//
//  PrivilegedOperationTests.swift
//  OnlySwitchTests
//

import Testing
@testable import OnlySwitch

struct PrivilegedOperationTests {
    @Test(arguments: [
        ("lowPowerMode", PrivilegedOperation.lowPowerMode),
        ("clamshellSleepDisabled", PrivilegedOperation.clamshellSleepDisabled)
    ])
    func requestNameAcceptsOnlyKnownOperation(name: String, expectedOperation: PrivilegedOperation) throws {
        let operation = try PrivilegedOperation(requestName: name)

        #expect(operation == expectedOperation)
    }

    @Test(arguments: [
        "/bin/sh -c whoami",
        "lowPowerMode; rm -rf /",
        "clamshellSleepDisabled --extra-argument",
        ""
    ])
    func requestNameRejectsArbitraryCommandLikeInput(_ name: String) {
        #expect(throws: PrivilegedOperationError.unsupportedOperation) {
            try PrivilegedOperation(requestName: name)
        }
    }

    @Test(arguments: [
        (PrivilegedOperation.lowPowerMode, true, ["-a", "lowpowermode", "1"]),
        (PrivilegedOperation.lowPowerMode, false, ["-a", "lowpowermode", "0"]),
        (PrivilegedOperation.clamshellSleepDisabled, true, ["-a", "disablesleep", "1"]),
        (PrivilegedOperation.clamshellSleepDisabled, false, ["-a", "disablesleep", "0"])
    ])
    func pmsetArgumentsAreFixedForEachOperation(
        operation: PrivilegedOperation,
        enabled: Bool,
        expectedArguments: [String]
    ) {
        #expect(operation.pmsetArguments(enabled: enabled) == expectedArguments)
    }

    @Test
    func requestDecodesOnlyTheTypedOperationAndBooleanState() throws {
        let request = try PrivilegedOperationRequest(requestName: "lowPowerMode", enabled: true)

        #expect(request == .init(operation: .lowPowerMode, enabled: true))
    }
}
